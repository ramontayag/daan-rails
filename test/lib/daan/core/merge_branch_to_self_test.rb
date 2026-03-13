# test/lib/daan/core/merge_branch_to_self_test.rb
require "test_helper"

class Daan::Core::MergeBranchToSelfTest < ActiveSupport::TestCase
  def fake_status(success:, exitstatus: 0)
    s = Object.new
    s.define_singleton_method(:success?) { success }
    s.define_singleton_method(:exitstatus) { exitstatus }
    s
  end

  def with_stub_open3(success: true, exitstatus: 0)
    commands_run = []
    status = fake_status(success: success, exitstatus: exitstatus)
    orig = Open3.method(:capture3)
    Open3.define_singleton_method(:capture3) { |*cmd, **_opts| commands_run << cmd; [ "", "", status ] }
    yield commands_run
  ensure
    Open3.define_singleton_method(:capture3, orig)
  end

  def with_stub_agent_loader
    synced_dirs = []
    orig = Daan::AgentLoader.method(:sync!)
    Daan::AgentLoader.define_singleton_method(:sync!) { |dir| synced_dirs << dir.to_s }
    yield synced_dirs
  ensure
    Daan::AgentLoader.define_singleton_method(:sync!, orig)
  end

  test "runs git fetch, checkout develop, merge in sequence" do
    tool = Daan::Core::MergeBranchToSelf.new

    with_stub_open3 do |commands_run|
      with_stub_agent_loader do
        tool.execute(branch: "feature/test-branch")
      end
      assert_equal [ %w[git fetch origin],
                     %w[git checkout develop],
                     %w[git merge origin/feature/test-branch] ], commands_run
    end
  end

  test "calls AgentLoader.sync! for both agent directories" do
    tool = Daan::Core::MergeBranchToSelf.new

    with_stub_open3 do
      with_stub_agent_loader do |synced_dirs|
        tool.execute(branch: "feature/test-branch")
        assert_includes synced_dirs, Rails.root.join("lib/daan/core/agents").to_s
        assert_includes synced_dirs, Rails.root.join("config/agents").to_s
      end
    end
  end

  test "raises if a git command fails" do
    tool = Daan::Core::MergeBranchToSelf.new

    with_stub_open3(success: false, exitstatus: 128) do
      assert_raises(RuntimeError) { tool.execute(branch: "feature/nonexistent") }
    end
  end
end
