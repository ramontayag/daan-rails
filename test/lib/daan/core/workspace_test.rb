# test/lib/daan/workspace_test.rb
require "test_helper"

class Daan::Core::WorkspaceTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    @workspace = Daan::Core::Workspace.new(@dir)
  end

  teardown { FileUtils.rm_rf(@dir) }

  test "resolve returns Pathname within workspace" do
    result = @workspace.resolve("hello.txt")
    assert_equal Pathname.new(@dir) / "hello.txt", result
  end

  test "resolve raises on path traversal" do
    assert_raises(ArgumentError) { @workspace.resolve("../../etc/passwd") }
  end

  test "resolve raises on absolute path escaping workspace" do
    assert_raises(ArgumentError) { @workspace.resolve("/etc/passwd") }
  end

  test "resolve allows nested paths" do
    result = @workspace.resolve("subdir/nested.txt")
    assert_equal Pathname.new(@dir) / "subdir/nested.txt", result
  end

  test "resolve raises on null byte in path" do
    assert_raises(ArgumentError) { @workspace.resolve("foo\0bar.txt") }
  end

  test "resolve raises on symlink escaping workspace" do
    outside = Tempfile.new("outside")
    symlink  = File.join(@dir, "evil.txt")
    File.symlink(outside.path, symlink)
    assert_raises(ArgumentError) { @workspace.resolve("evil.txt") }
  ensure
    File.unlink(symlink) rescue nil
    outside.close
    outside.unlink
  end

  test "to_s returns the root path string" do
    assert_equal @dir, @workspace.to_s
  end
end
