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

  test "raises on path traversal" do
    assert_raises(ArgumentError) { @tool.execute(path: "../../etc/passwd") }
  end

  test "raises if file does not exist" do
    assert_raises(Errno::ENOENT) { @tool.execute(path: "missing.txt") }
  end
end
