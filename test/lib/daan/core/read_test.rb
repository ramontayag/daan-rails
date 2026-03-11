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
    @tool.singleton_class.prepend(Daan::Core::SafeExecute)
    assert_match(/Error/, @tool.execute(path: "../../etc/passwd"))
  end

  test "returns error string if file does not exist" do
    @tool.singleton_class.prepend(Daan::Core::SafeExecute)
    assert_match(/Error/, @tool.execute(path: "missing.txt"))
  end

  test "returns error string when path is a directory" do
    @tool.singleton_class.prepend(Daan::Core::SafeExecute)
    assert_match(/Error/, @tool.execute(path: "."))
  end
end
