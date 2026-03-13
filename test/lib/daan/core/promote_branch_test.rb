require "test_helper"

class Daan::Core::PromoteBranchTest < ActiveSupport::TestCase
  def setup
    @tool = Daan::Core::PromoteBranch.new
    @app_root = Rails.root.to_s
  end

  # --- Development path ---

  test "dev: raises clear error when branch does not exist in origin" do
    with_dev_tool do |tool|
      tool.define_singleton_method(:run!) { |*| nil }
      tool.define_singleton_method(:branch_exists_in_origin?) { |*| false }
      error = assert_raises(RuntimeError) { tool.execute(branch: "nonexistent") }
      assert_includes error.message, "Branch 'nonexistent' not found in origin remote"
      assert_includes error.message, "git push origin nonexistent"
      assert_includes error.message, "Then try PromoteBranch again"
    end
  end

  test "dev: returns friendly message when branch is already merged" do
    with_dev_tool do |tool|
      tool.define_singleton_method(:run!) { |*| nil }
      tool.define_singleton_method(:branch_exists_in_origin?) { |*| true }
      tool.define_singleton_method(:branch_already_merged?) { |*| true }
      result = tool.execute(branch: "already-merged")
      assert_equal "Branch 'already-merged' is already merged into develop. No action needed.", result
    end
  end

  test "dev: provides helpful error context for merge failures" do
    with_dev_tool do |tool|
      tool.define_singleton_method(:run!) { |cmd, _| raise "merge conflict" if cmd.include?("merge") }
      tool.define_singleton_method(:branch_exists_in_origin?) { |*| true }
      tool.define_singleton_method(:branch_already_merged?) { |*| false }
      error = assert_raises(RuntimeError) { tool.execute(branch: "conflicting") }
      assert_includes error.message, "Failed to merge origin/conflicting into develop"
      assert_includes error.message, "Merge conflicts that need manual resolution"
      assert_includes error.message, "Original error: merge conflict"
    end
  end

  test "dev: success message includes branch name and production hint" do
    with_dev_tool do |tool|
      tool.define_singleton_method(:run!) { |*| nil }
      tool.define_singleton_method(:branch_exists_in_origin?) { |*| true }
      tool.define_singleton_method(:branch_already_merged?) { |*| false }
      with_stub_agent_loader_sync do
        result = tool.execute(branch: "feature/my-change")
        assert_includes result, "feature/my-change"
        assert_includes result, "pull request"
      end
    end
  end

  # --- Production path ---

  test "prod: opens a pull request and returns the URL" do
    with_prod_tool do |tool|
      with_open3(["https://github.com/owner/repo/pull/42\n", "", fake_status(true)]) do
        result = tool.execute(branch: "feature/my-change", title: "My change", body: "Details")
        assert_equal "https://github.com/owner/repo/pull/42", result
      end
    end
  end

  test "prod: raises on gh failure" do
    with_prod_tool do |tool|
      with_open3(["", "some error", fake_status(false)]) do
        error = assert_raises(RuntimeError) { tool.execute(branch: "feature/x", title: "T", body: "B") }
        assert_includes error.message, "gh pr create failed"
      end
    end
  end

  # --- Shared helpers ---

  test "branch_exists_in_origin? returns true when ls-remote finds the branch" do
    with_open3(["abc123\trefs/heads/existing\n", "", fake_status(true)]) do
      assert @tool.send(:branch_exists_in_origin?, "existing", @app_root)
    end
  end

  test "branch_exists_in_origin? returns false when ls-remote returns empty" do
    with_open3(["", "", fake_status(true)]) do
      refute @tool.send(:branch_exists_in_origin?, "missing", @app_root)
    end
  end

  test "branch_already_merged? returns true when branch commit equals merge-base" do
    call_count = 0
    responses = [
      ["abc123\n", "", fake_status(true)],
      ["def456\n", "", fake_status(true)],
      ["abc123\n", "", fake_status(true)]
    ]
    Open3.singleton_class.define_method(:capture3) do |*|
      responses[call_count].tap { call_count += 1 }
    end
    assert @tool.send(:branch_already_merged?, "merged", @app_root)
  ensure
    Open3.singleton_class.remove_method(:capture3)
  end

  test "branch_already_merged? returns false when branch commit differs from merge-base" do
    call_count = 0
    responses = [
      ["abc123\n", "", fake_status(true)],
      ["def456\n", "", fake_status(true)],
      ["def456\n", "", fake_status(true)]
    ]
    Open3.singleton_class.define_method(:capture3) do |*|
      responses[call_count].tap { call_count += 1 }
    end
    refute @tool.send(:branch_already_merged?, "unmerged", @app_root)
  ensure
    Open3.singleton_class.remove_method(:capture3)
  end

  private

  def with_dev_tool
    tool = Daan::Core::PromoteBranch.new
    tool.define_singleton_method(:development?) { true }
    yield tool
  end

  def with_prod_tool
    tool = Daan::Core::PromoteBranch.new
    tool.define_singleton_method(:development?) { false }
    yield tool
  end

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

  def with_stub_agent_loader_sync
    sc = Daan::AgentLoader.singleton_class
    sc.alias_method(:__orig_sync__, :sync!)
    sc.define_method(:sync!) { |*| nil }
    yield
  ensure
    sc.alias_method(:sync!, :__orig_sync__)
    sc.remove_method(:__orig_sync__)
  end
end
