require "test_helper"

class Daan::Core::ConversationRunnerOrientationTest < ActiveSupport::TestCase
  setup do
    @workspace_dir = Dir.mktmpdir
    system("git", "init", @workspace_dir, out: File::NULL, err: File::NULL)
    system("git", "-C", @workspace_dir, "commit", "--allow-empty", "-m", "initial", out: File::NULL, err: File::NULL)

    @agent = Daan::Core::Agent.new(
      name: "developer", display_name: "Dev",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You are a developer.", max_steps: 10,
      workspace: Daan::Core::Workspace.new(@workspace_dir)
    )
    Daan::Core::AgentRegistry.register(@agent)
  end

  teardown do
    FileUtils.rm_rf(@workspace_dir)
  end

  test "injects orientation message when workspace changed hands" do
    chat_a = Chat.create!(agent_name: "developer")
    chat_b = Chat.create!(agent_name: "developer")
    chat_b.messages.create!(role: "user", content: "Say exactly: ok", visible: true)

    WorkspaceLock.acquire(chat: chat_a, agent_name: "developer")
    WorkspaceLock.release(chat: chat_a, agent_name: "developer")

    VCR.use_cassette("workspace_lock/orientation_after_handoff") do
      Daan::Core::ConversationRunner.call(chat_b)
    end

    orientation = chat_b.messages.where(role: "user", visible: false)
                        .where("content LIKE ?", "%Workspace was used by another chat%")
    assert orientation.exists?, "Should inject workspace orientation message"
  end

  test "does not inject orientation when same chat re-acquires" do
    chat = Chat.create!(agent_name: "developer")
    chat.messages.create!(role: "user", content: "Say exactly: ok", visible: true)

    VCR.use_cassette("workspace_lock/no_orientation_same_chat") do
      Daan::Core::ConversationRunner.call(chat)
    end

    orientation = chat.messages.where(role: "user", visible: false)
                      .where("content LIKE ?", "%Workspace was used by another chat%")
    refute orientation.exists?, "Should not inject orientation for same chat"
  end
end
