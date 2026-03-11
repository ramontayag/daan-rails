# test/lib/daan/core/read_test.rb
require "test_helper"

class Daan::Core::ReadTest < ActiveSupport::TestCase
  setup do
    dir = Dir.mktmpdir
    @workspace = Daan::Workspace.new(dir)
    @tool = Daan::Core::Read.new(workspace: @workspace)
    File.write(File.join(dir, "hello.txt"), "Hello, world!")
  end

  teardown { FileUtils.rm_rf(@workspace.root) }

  test "reads a file within the workspace" do
    assert_equal "Hello, world!", @tool.execute(path: "hello.txt")
  end

  test "returns error string on path traversal" do
    result = @tool.execute(path: "../../etc/passwd")
    assert_match(/Error/, result)
  end

  test "returns error string if file does not exist" do
    result = @tool.execute(path: "missing.txt")
    assert_match(/Error/, result)
  end

  test "returns error string when path is a directory" do
    result = @tool.execute(path: ".")
    assert_match(/Error/, result)
  end
end
