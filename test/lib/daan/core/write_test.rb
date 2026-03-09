# test/lib/daan/core/write_test.rb
require "test_helper"

class Daan::Core::WriteTest < ActiveSupport::TestCase
  setup do
    @workspace = Dir.mktmpdir
    workspace = @workspace
    @tool = Class.new(Daan::Core::Write) do
      @workspace = workspace
      class << self; attr_reader :workspace; end
    end.new
  end

  teardown { FileUtils.rm_rf(@workspace) }

  test "writes a file to the workspace" do
    @tool.execute(path: "output.txt", content: "Test content")
    assert_equal "Test content", File.read(File.join(@workspace, "output.txt"))
  end

  test "returns a confirmation string" do
    result = @tool.execute(path: "output.txt", content: "Test content")
    assert_includes result, "output.txt"
  end

  test "creates intermediate directories" do
    @tool.execute(path: "subdir/nested.txt", content: "hi")
    assert File.exist?(File.join(@workspace, "subdir", "nested.txt"))
  end
end
