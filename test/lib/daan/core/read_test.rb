# test/lib/daan/core/read_test.rb
require "test_helper"

class Daan::Core::ReadTest < ActiveSupport::TestCase
  setup do
    dir = Dir.mktmpdir
    @workspace = Daan::Core::Workspace.new(dir)
    @tool = Daan::Core::Read.new(workspace: @workspace)
    File.write(File.join(dir, "hello.txt"), "Hello, world!")
  end

  teardown { FileUtils.rm_rf(@workspace.root) }

  test "reads a file within the workspace" do
    assert_equal "Hello, world!", @tool.execute(path: "hello.txt")
  end

  test "returns only the first 2000 lines by default for large files" do
    lines = (1..2500).map { |i| "line #{i}\n" }
    File.write(File.join(@workspace.root, "big.txt"), lines.join)

    result = @tool.execute(path: "big.txt")

    assert_equal lines[0..1999].join, result.lines.first(2000).join
    assert_match(/File truncated/, result)
    assert_match(/2000/, result)
    assert_match(/2500/, result)
  end

  test "does not truncate files within the 2000 line limit" do
    lines = (1..100).map { |i| "line #{i}\n" }
    File.write(File.join(@workspace.root, "small.txt"), lines.join)

    result = @tool.execute(path: "small.txt")

    assert_equal lines.join, result
    assert_no_match(/File truncated/, result)
  end

  test "reads from start_line when specified" do
    lines = (1..10).map { |i| "line #{i}\n" }
    File.write(File.join(@workspace.root, "numbered.txt"), lines.join)

    result = @tool.execute(path: "numbered.txt", start_line: 3)

    assert result.start_with?("line 3\n")
    refute result.include?("line 2\n")
  end

  test "reads up to end_line when specified" do
    lines = (1..10).map { |i| "line #{i}\n" }
    File.write(File.join(@workspace.root, "numbered.txt"), lines.join)

    result = @tool.execute(path: "numbered.txt", end_line: 3)

    assert result.include?("line 3\n")
    refute result.include?("line 4\n")
  end

  test "reads a specific range with start_line and end_line" do
    lines = (1..10).map { |i| "line #{i}\n" }
    File.write(File.join(@workspace.root, "numbered.txt"), lines.join)

    result = @tool.execute(path: "numbered.txt", start_line: 2, end_line: 4)

    assert_equal lines[1..3].join, result
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
