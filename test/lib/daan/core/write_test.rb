# test/lib/daan/core/write_test.rb
require "test_helper"

class Daan::Core::WriteTest < ActiveSupport::TestCase
  setup do
    dir = Dir.mktmpdir
    @workspace = Daan::Workspace.new(dir)
    ws = @workspace
    @tool = Class.new(Daan::Core::Write) do
      @workspace = ws
      class << self; attr_reader :workspace; end
    end.new
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
end
