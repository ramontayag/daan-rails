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

  test "raises on disallowed binary" do
    error = assert_raises(RuntimeError) do
      @tool.execute(commands: [["rm", "-rf", "."]])
    end
    assert_match(/not allowed/, error.message)
  end

  test "raises on empty allowed_commands list" do
    tool = Daan::Core::Bash.new(workspace: @workspace, allowed_commands: [])
    error = assert_raises(RuntimeError) do
      tool.execute(commands: [["echo", "hi"]])
    end
    assert_match(/not allowed/, error.message)
  end

  test "raises when a command fails" do
    # workspace_dir is not a git repo — git status exits non-zero
    assert_raises(RuntimeError) do
      @tool.execute(commands: [["git", "status"]])
    end
  end

  test "raises on second command failure and returns no partial output" do
    error = assert_raises(RuntimeError) do
      @tool.execute(commands: [["echo", "step one"], ["git", "status"]])
    end
    assert_match(/git status/, error.message)
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

  test "raises when path escapes workspace" do
    assert_raises(ArgumentError) do
      @tool.execute(commands: [["echo", "hi"]], path: "../escape")
    end
  end
end
