# test/lib/daan/core/write_test.rb
require "test_helper"

class Daan::Core::WriteTest < ActiveSupport::TestCase
  setup do
    dir = Dir.mktmpdir
    @workspace = Daan::Workspace.new(dir)
    @tool = Daan::Core::Write.new(workspace: @workspace)
  end

  teardown { FileUtils.rm_rf(@workspace.root) }

  test "writes a file to the workspace" do
    @tool.execute(path: "output.txt", content: "Test content")
    assert_equal "Test content", (@workspace.root / "output.txt").read
  end

  test "returns a confirmation string" do
    result = @tool.execute(path: "output.txt", content: "Test content")
    assert_includes result, "output.txt"
  end

  test "creates intermediate directories" do
    @tool.execute(path: "subdir/nested.txt", content: "hi")
    assert (@workspace.root / "subdir" / "nested.txt").exist?
  end

  test "returns error string on path traversal" do
    @tool.singleton_class.prepend(Daan::Core::SafeExecute)
    assert_match(/Error/, @tool.execute(path: "../../etc/passwd", content: "bad"))
  end
end
