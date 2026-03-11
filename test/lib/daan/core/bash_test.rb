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
    result = @tool.execute(commands: [["echo", "hello"]])
    assert_includes result, "hello"
  end

  test "runs multiple commands and returns all output" do
    result = @tool.execute(commands: [["echo", "first"], ["echo", "second"]])
    assert_includes result, "first"
    assert_includes result, "second"
  end

  test "returns empty string for empty commands array" do
    assert_equal "", @tool.execute(commands: [])
  end

  test "returns error string on disallowed binary" do
    @tool.singleton_class.prepend(Daan::Core::SafeExecute)
    assert_match(/not allowed/, @tool.execute(commands: [["rm", "-rf", "."]]))
  end

  test "returns error string on empty allowed_commands list" do
    tool = Daan::Core::Bash.new(workspace: @workspace, allowed_commands: [])
    tool.singleton_class.prepend(Daan::Core::SafeExecute)
    assert_match(/not allowed/, tool.execute(commands: [["echo", "hi"]]))
  end

  test "returns error string when a command fails" do
    @tool.singleton_class.prepend(Daan::Core::SafeExecute)
    result = @tool.execute(commands: [["git", "status"]])
    assert_match(/git status/, result)
    assert_match(/failed/, result)
  end

  test "returns error string on second command failure" do
    @tool.singleton_class.prepend(Daan::Core::SafeExecute)
    result = @tool.execute(commands: [["echo", "step one"], ["git", "status"]])
    assert_match(/git status/, result)
    assert_match(/failed/, result)
  end

  test "runs commands in workspace root by default" do
    result = @tool.execute(commands: [["pwd"]])
    assert_includes result, @workspace_dir
  end

  test "runs commands in specified subdirectory" do
    subdir = File.join(@workspace_dir, "subdir")
    FileUtils.mkdir_p(subdir)

    result = @tool.execute(commands: [["pwd"]], path: "subdir")
    assert_includes result, File.join(@workspace_dir, "subdir")
  end

  test "accepts commands as a JSON-encoded string (LLM fallback)" do
    result = @tool.execute(commands: '[["echo", "hello"]]')
    assert_includes result, "hello"
  end

  test "returns error string when path escapes workspace" do
    @tool.singleton_class.prepend(Daan::Core::SafeExecute)
    assert_match(/escape/, @tool.execute(commands: [["echo", "hi"]], path: "../escape"))
  end
end
