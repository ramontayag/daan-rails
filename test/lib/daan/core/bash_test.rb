require "test_helper"

class Daan::Core::BashTest < ActiveSupport::TestCase
  setup do
    @workspace_dir = Dir.mktmpdir
    @workspace = Daan::Workspace.new(@workspace_dir)
    @tool = Daan::Core::Bash.new(
      workspace: @workspace,
      allowed_commands: %w[echo git pwd sh]
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
    result = @tool.execute(commands: [ [ "sh", "-c", "exit 1" ] ])
    assert_match(/sh -c exit 1/, result)
    assert_match(/failed/, result)
  end

  test "returns error string on second command failure" do
    @tool.singleton_class.prepend(Daan::Core::SafeExecute)
    result = @tool.execute(commands: [ [ "echo", "step one" ], [ "sh", "-c", "exit 1" ] ])
    assert_match(/sh -c exit 1/, result)
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
    # Simulate what happens with `git rebase -i`: the command spawns a child that
    # keeps stdout/stderr pipes open even after the parent process is killed.
    # Without the fix, out_thread.join in the rescue block blocks forever because
    # the child still holds the write end of the pipe.
    script = Tempfile.new([ "pipe_hog", ".sh" ])
    script.write(<<~SH)
      #!/bin/sh
      # Spawn a background child that sleeps indefinitely (keeps pipes open).
      sleep 60 &
      # Parent then sleeps, waiting to be killed.
      sleep 60
    SH
    script.close
    File.chmod(0o755, script.path)

    tool = Daan::Core::Bash.new(workspace: @workspace, allowed_commands: %w[sh])
    tool.singleton_class.prepend(Daan::Core::SafeExecute)

    started_at = Time.now
    result = tool.execute(commands: [ [ "sh", script.path ] ], timeout_seconds: 0.5)
    elapsed = Time.now - started_at

    assert_match(/timed out/, result)
    assert elapsed < 3, "expected to return within 3s but took #{elapsed.round(2)}s"
  ensure
    script&.unlink
  end
end
