require "test_helper"

class Daan::Core::PromoteBranchTest < ActiveSupport::TestCase
  def setup
    @tool = Daan::Core::PromoteBranch.new
    @app_root = Rails.root.to_s
  end

  # --- Development path ---

  test "dev: raises when repo_path is not provided" do
    with_dev_tool do |tool|
      tool.define_singleton_method(:run!) { |*| nil }
      error = assert_raises(RuntimeError) { tool.execute(branch: "feat", tests_passed: true) }
      assert_includes error.message, "repo_path is required"
    end
  end

  test "dev: raises clear error when branch does not exist in origin" do
    with_dev_tool do |tool|
      tool.define_singleton_method(:run!) { |*| nil }
      tool.define_singleton_method(:branch_exists_in_origin?) { |*| false }
      error = assert_raises(RuntimeError) { tool.execute(branch: "nonexistent", tests_passed: true, repo_path: "daan-rails") }
      assert_includes error.message, "Branch 'nonexistent' not found in origin remote"
      assert_includes error.message, "git push origin nonexistent"
      assert_includes error.message, "Then try PromoteBranch again"
    end
  end

  test "dev: skips merge when branch is already merged but still syncs running app" do
    with_dev_tool do |tool|
      tool.define_singleton_method(:run!) { |*| nil }
      tool.define_singleton_method(:branch_exists_in_origin?) { |*| true }
      tool.define_singleton_method(:branch_already_merged?) { |*| true }
      with_stub_agent_loader_sync do
        result = tool.execute(branch: "already-merged", tests_passed: true, repo_path: "daan-rails")
        assert_includes result, "already-merged"
        assert_includes result, "pull request"
      end
    end
  end

  test "dev: refuses branch not based on origin/main" do
    with_dev_tool do |tool|
      tool.define_singleton_method(:run!) { |*| nil }
      tool.define_singleton_method(:branch_exists_in_origin?) { |*| true }
      tool.define_singleton_method(:branch_already_merged?) { |*| false }
      tool.define_singleton_method(:branch_based_on_main?) { |*| false }
      error = assert_raises(RuntimeError) { tool.execute(branch: "stale-branch", tests_passed: true, repo_path: "daan-rails") }
      assert_includes error.message, "not based on the latest origin/main"
      assert_includes error.message, "rebase"
    end
  end

  test "dev: leaves merge in progress on conflict and instructs developer to resolve" do
    with_dev_tool do |tool|
      tool.define_singleton_method(:run!) do |cmd, _dir|
        raise "merge conflict" if cmd.include?("merge")
      end
      tool.define_singleton_method(:branch_exists_in_origin?) { |*| true }
      tool.define_singleton_method(:branch_already_merged?) { |*| false }
      tool.define_singleton_method(:branch_based_on_main?) { |*| true }
      error = assert_raises(RuntimeError) { tool.execute(branch: "conflicting", tests_passed: true, repo_path: "daan-rails") }
      assert_includes error.message, "Merge conflict merging origin/conflicting into develop"
      assert_includes error.message, "merge is still in progress"
      assert_includes error.message, "git push origin develop"
      assert_includes error.message, "call PromoteBranch again"
    end
  end

  test "dev: success message includes branch name and production hint" do
    with_dev_tool do |tool|
      tool.define_singleton_method(:run!) { |*| nil }
      tool.define_singleton_method(:branch_exists_in_origin?) { |*| true }
      tool.define_singleton_method(:branch_already_merged?) { |*| false }
      tool.define_singleton_method(:branch_based_on_main?) { |*| true }
      with_stub_agent_loader_sync do
        result = tool.execute(branch: "feature/my-change", tests_passed: true, repo_path: "daan-rails")
        assert_includes result, "feature/my-change"
        assert_includes result, "pull request"
      end
    end
  end

  # --- Production path ---

  test "prod: opens a pull request and returns the URL" do
    with_prod_tool do |tool|
      with_open3([ "https://github.com/owner/repo/pull/42\n", "", fake_status(true) ]) do
        result = tool.execute(branch: "feature/my-change", tests_passed: true, title: "My change", body: "Details")
        assert_equal "https://github.com/owner/repo/pull/42", result
      end
    end
  end

  test "prod: raises on gh failure" do
    with_prod_tool do |tool|
      with_open3([ "", "some error", fake_status(false) ]) do
        error = assert_raises(RuntimeError) { tool.execute(branch: "feature/x", tests_passed: true, title: "T", body: "B") }
        assert_includes error.message, "gh pr create failed"
      end
    end
  end

  # --- Shared helpers ---

  test "branch_exists_in_origin? returns true when ls-remote finds the branch" do
    with_open3([ "abc123\trefs/heads/existing\n", "", fake_status(true) ]) do
      assert @tool.send(:branch_exists_in_origin?, "existing", @app_root)
    end
  end

  test "branch_exists_in_origin? returns false when ls-remote returns empty" do
    with_open3([ "", "", fake_status(true) ]) do
      refute @tool.send(:branch_exists_in_origin?, "missing", @app_root)
    end
  end

  test "branch_already_merged? returns true when branch commit equals merge-base" do
    call_count = 0
    responses = [
      [ "abc123\n", "", fake_status(true) ],
      [ "def456\n", "", fake_status(true) ],
      [ "abc123\n", "", fake_status(true) ]
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
      [ "abc123\n", "", fake_status(true) ],
      [ "def456\n", "", fake_status(true) ],
      [ "def456\n", "", fake_status(true) ]
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
    workspace = Struct.new(:root).new(Pathname("/tmp/fake-workspace"))
    tool = Daan::Core::PromoteBranch.new(workspace: workspace)
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
