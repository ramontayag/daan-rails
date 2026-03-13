require "test_helper"

class Daan::Core::MergeBranchToSelfTest < ActiveSupport::TestCase
  def setup
    @tool = Daan::Core::MergeBranchToSelf.new
    @app_root = Rails.root.to_s
  end

  test "raises clear error when branch does not exist in origin" do
    @tool.define_singleton_method(:run!) { |*| nil }
    @tool.define_singleton_method(:branch_exists_in_origin?) { |*| false }
    error = assert_raises(RuntimeError) { @tool.execute(branch: "nonexistent-branch") }
    assert_includes error.message, "Branch 'nonexistent-branch' not found in origin remote"
    assert_includes error.message, "git push origin nonexistent-branch"
    assert_includes error.message, "Then try MergeBranchToSelf again"
  end

  test "returns friendly message when branch is already merged" do
    @tool.define_singleton_method(:run!) { |*| nil }
    @tool.define_singleton_method(:branch_exists_in_origin?) { |*| true }
    @tool.define_singleton_method(:branch_already_merged?) { |*| true }
    result = @tool.execute(branch: "already-merged-branch")
    assert_equal "Branch 'already-merged-branch' is already merged into develop. No action needed.", result
  end

  test "provides helpful error context for merge failures" do
    @tool.define_singleton_method(:run!) { |cmd, _| raise "merge conflict" if cmd.include?("merge") }
    @tool.define_singleton_method(:branch_exists_in_origin?) { |*| true }
    @tool.define_singleton_method(:branch_already_merged?) { |*| false }
    error = assert_raises(RuntimeError) { @tool.execute(branch: "conflicting-branch") }
    assert_includes error.message, "Failed to merge origin/conflicting-branch into develop"
    assert_includes error.message, "Merge conflicts that need manual resolution"
    assert_includes error.message, "Branch has diverged from develop"
    assert_includes error.message, "Original error: merge conflict"
  end

  test "branch_exists_in_origin? detects existing branch" do
    with_open3(["abc123\trefs/heads/existing-branch\n", "", fake_status(true)]) do
      assert @tool.send(:branch_exists_in_origin?, "existing-branch", @app_root)
    end
  end

  test "branch_exists_in_origin? detects missing branch" do
    with_open3(["", "", fake_status(true)]) do
      refute @tool.send(:branch_exists_in_origin?, "missing-branch", @app_root)
    end
  end

  test "branch_already_merged? detects already merged branch" do
    call_count = 0
    responses = [
      ["abc123\n", "", fake_status(true)],
      ["def456\n", "", fake_status(true)],
      ["abc123\n", "", fake_status(true)]
    ]
    Open3.singleton_class.define_method(:capture3) { |*| responses[call_count].tap { call_count += 1 } }
    assert @tool.send(:branch_already_merged?, "merged-branch", @app_root)
  ensure
    Open3.singleton_class.remove_method(:capture3)
  end

  test "branch_already_merged? detects unmerged branch" do
    call_count = 0
    responses = [
      ["abc123\n", "", fake_status(true)],
      ["ghi789\n", "", fake_status(true)],
      ["def456\n", "", fake_status(true)]
    ]
    Open3.singleton_class.define_method(:capture3) { |*| responses[call_count].tap { call_count += 1 } }
    refute @tool.send(:branch_already_merged?, "unmerged-branch", @app_root)
  ensure
    Open3.singleton_class.remove_method(:capture3)
  end

  private

  def with_open3(response)
    Open3.singleton_class.define_method(:capture3) { |*| response }
    yield
  ensure
    Open3.singleton_class.remove_method(:capture3)
  end

  def fake_status(success)
    s = Object.new
    s.define_singleton_method(:success?) { success }
    s.define_singleton_method(:exitstatus) { success ? 0 : 1 }
    s
  end
end
