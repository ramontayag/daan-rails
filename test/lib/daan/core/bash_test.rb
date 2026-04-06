require "test_helper"

class Daan::Core::BashTest < ActiveSupport::TestCase
  setup do
    @workspace_dir = Dir.mktmpdir
    @workspace = Daan::Workspace.new(@workspace_dir)
    @tool = Daan::Core::Bash.new(
      workspace: @workspace,
      allowed_commands: %w[echo git pwd cat]
    )
  end

  teardown do
    FileUtils.rm_rf(@workspace_dir)
  end

  test "runs a single allowed command and returns its output" do
    result = @tool.execute(commands: [ [ "echo", "hello" ] ])
    assert_includes result, "hello"
  end

  test "runs multiple commands and returns all output" do
    result = @tool.execute(commands: [ [ "echo", "first" ], [ "echo", "second" ] ])
    assert_includes result, "first"
    assert_includes result, "second"
  end

  test "returns empty string for empty commands array" do
    assert_equal "", @tool.execute(commands: [])
  end

  test "returns error string on disallowed binary" do
    @tool.singleton_class.prepend(Daan::Core::SafeExecute)
    assert_match(/not allowed/, @tool.execute(commands: [ [ "rm", "-rf", "." ] ]))
  end

  test "returns error string on empty allowed_commands list" do
    tool = Daan::Core::Bash.new(workspace: @workspace, allowed_commands: [])
    tool.singleton_class.prepend(Daan::Core::SafeExecute)
    assert_match(/not allowed/, tool.execute(commands: [ [ "echo", "hi" ] ]))
  end

  test "returns error string when a command fails" do
    @tool.singleton_class.prepend(Daan::Core::SafeExecute)
    result = @tool.execute(commands: [ [ "git", "log" ] ])
    assert_match(/failed/, result)
  end

  test "returns error string on second command failure" do
    @tool.singleton_class.prepend(Daan::Core::SafeExecute)
    result = @tool.execute(commands: [ [ "echo", "step one" ], [ "git", "log" ] ])
    assert_match(/failed/, result)
  end

  test "returns error when shell interpreter is used even if in allowed_commands" do
    tool = Daan::Core::Bash.new(workspace: @workspace, allowed_commands: %w[sh bash])
    tool.singleton_class.prepend(Daan::Core::SafeExecute)
    result = tool.execute(commands: [ [ "sh", "-c", "echo hi" ] ])
    assert_match(/shell interpreter.*not allowed/, result)
  end

  test "runs commands in workspace root by default" do
    result = @tool.execute(commands: [ [ "pwd" ] ])
    assert_includes result, @workspace_dir
  end

  test "runs commands in specified subdirectory" do
    subdir = File.join(@workspace_dir, "subdir")
    FileUtils.mkdir_p(subdir)

    result = @tool.execute(commands: [ [ "pwd" ] ], path: "subdir")
    assert_includes result, File.join(@workspace_dir, "subdir")
  end

  test "accepts commands as a JSON-encoded string (LLM fallback)" do
    result = @tool.execute(commands: '[["echo", "hello"]]')
    assert_includes result, "hello"
  end

  test "returns error string when path escapes workspace" do
    @tool.singleton_class.prepend(Daan::Core::SafeExecute)
    assert_match(/escape/, @tool.execute(commands: [ [ "echo", "hi" ] ], path: "../escape"))
  end

  test "returns error when an argument is an absolute path outside the workspace" do
    @tool.singleton_class.prepend(Daan::Core::SafeExecute)
    result = @tool.execute(commands: [ [ "echo", "/etc/passwd" ] ])
    assert_match(/escape/, result)
  end

  test "returns error when an argument uses .. to traverse outside the workspace" do
    @tool.singleton_class.prepend(Daan::Core::SafeExecute)
    result = @tool.execute(commands: [ [ "echo", "../../.." ] ])
    assert_match(/escape/, result)
  end

  test "allows arguments that are absolute paths inside the workspace" do
    path_inside = File.join(@workspace_dir, "somefile.txt")
    result = @tool.execute(commands: [ [ "echo", path_inside ] ])
    assert_includes result, path_inside
  end

  test "returns error when a symlink inside workspace points outside" do
    @tool.singleton_class.prepend(Daan::Core::SafeExecute)
    File.symlink("/etc/passwd", File.join(@workspace_dir, "sneaky_link"))

    result = @tool.execute(commands: [ [ "echo", "sneaky_link" ] ])
    assert_match(/escape/, result)
  end

  test "allows a symlink inside workspace that points to another workspace file" do
    target = File.join(@workspace_dir, "real_file.txt")
    File.write(target, "hello")
    File.symlink(target, File.join(@workspace_dir, "internal_link"))

    result = @tool.execute(commands: [ [ "echo", "internal_link" ] ])
    assert_includes result, "internal_link"
  end

  test "returns error when a relative path with slash resolves outside workspace via symlink" do
    @tool.singleton_class.prepend(Daan::Core::SafeExecute)
    subdir = File.join(@workspace_dir, "sub")
    FileUtils.mkdir_p(subdir)
    File.symlink("/etc", File.join(subdir, "escape"))

    result = @tool.execute(commands: [ [ "echo", "sub/escape/passwd" ] ])
    assert_match(/escape/, result)
  end

  test "returns error when argument contains null byte" do
    @tool.singleton_class.prepend(Daan::Core::SafeExecute)
    result = @tool.execute(commands: [ [ "echo", "file\0name" ] ])
    assert_match(/null byte/, result)
  end

  test "returns error when flag with = contains path outside workspace" do
    @tool.singleton_class.prepend(Daan::Core::SafeExecute)
    result = @tool.execute(commands: [ [ "git", "diff", "--output=/tmp/evil" ] ])
    assert_match(/escape/, result)
  end

  test "allows flag with = containing path inside workspace" do
    path_inside = File.join(@workspace_dir, "output.txt")
    result = @tool.execute(commands: [ [ "echo", "--output=#{path_inside}" ] ])
    assert_includes result, "--output=#{path_inside}"
  end

  test "allows plain arguments that do not look like paths" do
    result = @tool.execute(commands: [ [ "echo", "hello world" ] ])
    assert_includes result, "hello world"
  end

  test "includes stderr in successful command output" do
    # git init writes "Initialized..." to stdout and hints to stderr
    # both should appear in the result so LLMs see the full picture
    result = @tool.execute(commands: [ [ "git", "init" ] ])
    assert_includes result, "Initialized"
    assert_includes result, "hint:"
  end

  test "kills subprocess and returns error on timeout" do
    tool = Daan::Core::Bash.new(workspace: @workspace, allowed_commands: %w[sleep])
    tool.singleton_class.prepend(Daan::Core::SafeExecute)
    result = tool.execute(commands: [ [ "sleep", "10" ] ], timeout_seconds: 0.2)
    assert_match(/timed out/, result)
  end

  test "default timeout is used when not specified" do
    result = @tool.execute(commands: [ [ "echo", "hi" ] ])
    assert_includes result, "hi"
  end

  test "returns timed out error promptly when child process holds pipe open after parent is killed" do
    tool = Daan::Core::Bash.new(workspace: @workspace, allowed_commands: %w[sleep])
    tool.singleton_class.prepend(Daan::Core::SafeExecute)

    started_at = Time.now
    result = tool.execute(commands: [ [ "sleep", "60" ] ], timeout_seconds: 0.5)
    elapsed = Time.now - started_at

    assert_match(/timed out/, result)
    assert elapsed < 3, "expected to return within 3s but took #{elapsed.round(2)}s"
  end
end
