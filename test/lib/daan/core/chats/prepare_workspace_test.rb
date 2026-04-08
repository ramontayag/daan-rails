# test/lib/daan/chats/prepare_workspace_test.rb
require "test_helper"

class Daan::Core::Chats::PrepareWorkspaceTest < ActiveSupport::TestCase
  test "creates workspace root directory when agent has a workspace" do
    root = Pathname.new(Dir.mktmpdir) / "workspace"
    workspace = Minitest::Mock.new
    workspace.expect(:root, root)

    agent = Minitest::Mock.new
    agent.expect(:workspace, workspace)

    Daan::Core::Chats::PrepareWorkspace.call(agent)

    assert root.exist?
  ensure
    FileUtils.rm_rf(root.parent)
  end

  test "does nothing when agent has no workspace" do
    agent = Minitest::Mock.new
    agent.expect(:workspace, nil)

    assert_nothing_raised { Daan::Core::Chats::PrepareWorkspace.call(agent) }
  end
end
