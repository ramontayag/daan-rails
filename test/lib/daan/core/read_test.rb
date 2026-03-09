# test/lib/daan/core/read_test.rb
require "test_helper"

class Daan::Core::ReadTest < ActiveSupport::TestCase
  setup do
    @workspace = Dir.mktmpdir
    workspace = @workspace
    @tool = Class.new(Daan::Core::Read) do
      @workspace = workspace
      class << self; attr_reader :workspace; end
    end.new
    File.write(File.join(@workspace, "hello.txt"), "Hello, world!")
  end

  teardown { FileUtils.rm_rf(@workspace) }

  test "reads a file within the workspace" do
    assert_equal "Hello, world!", @tool.execute(path: "hello.txt")
  end

  test "raises if file does not exist" do
    assert_raises(RuntimeError) { @tool.execute(path: "missing.txt") }
  end
end
