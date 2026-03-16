require "test_helper"

class Daan::Core::BashTest < ActiveSupport::TestCase
  setup do
    @workspace_dir = Dir.mktmpdir
    @workspace = Daan::Workspace.new(@workspace_dir)
    @tool = Daan::Core::Bash.new(
      workspace: @workspace,
      allowed_commands: %w[echo git pwd]
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
    result = @tool.execute(commands: [ [ "git", "status" ] ])
    assert_match(/git status/, result)
    assert_match(/failed/, result)
  end

  test "returns error string on second command failure" do
    @tool.singleton_class.prepend(Daan::Core::SafeExecute)
    result = @tool.execute(commands: [ [ "echo", "step one" ], [ "git", "status" ] ])
    assert_match(/git status/, result)
    assert_match(/failed/, result)
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

  test "includes stderr in successful command output" do
    # git init writes "Initialized..." to stdout and hints to stderr
    # both should appear in the result so LLMs see the full picture
    result = @tool.execute(commands: [ [ "git", "init" ] ])
    assert_includes result, "Initialized"
    assert_includes result, "hint:"
  end

  test "returns error string when command exceeds timeout" do
    tool = Daan::Core::Bash.new(workspace: @workspace, allowed_commands: %w[sleep])
    tool.singleton_class.prepend(Daan::Core::SafeExecute)
    result = tool.execute(commands: [ [ "sleep", "10" ] ], timeout: 0.1)
    assert_match(/timed out/, result)
    assert_match(/sleep 10/, result)
  end

  test "timeout applies per command" do
    tool = Daan::Core::Bash.new(workspace: @workspace, allowed_commands: %w[echo sleep])
    tool.singleton_class.prepend(Daan::Core::SafeExecute)
    result = tool.execute(commands: [ [ "echo", "fast" ], [ "sleep", "10" ] ], timeout: 0.1)
    assert_match(/timed out/, result)
  end

  test "default timeout is used when not specified" do
    result = @tool.execute(commands: [ [ "echo", "hi" ] ])
    assert_includes result, "hi"
  end
end
