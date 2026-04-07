require "test_helper"

class Daan::Chats::ReleaseWorkspaceTest < ActiveSupport::TestCase
  setup do
    @agent = Daan::Agent.new(
      name: "developer", display_name: "Dev",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You are a developer.", max_steps: 10
    )
    Daan::AgentRegistry.register(@agent)
    @chat = Chat.create!(agent_name: "developer")
    WorkspaceLock.acquire(chat: @chat, agent_name: "developer")
  end

  test "releases the lock" do
    Daan::Chats::ReleaseWorkspace.call(@chat)
    other_chat = Chat.create!(agent_name: "developer")
    result = WorkspaceLock.acquire(chat: other_chat, agent_name: "developer")
    assert result.acquired?
  end

  test "is safe to call when no lock exists" do
    assert_nothing_raised do
      Daan::Chats::ReleaseWorkspace.call(Chat.create!(agent_name: "developer"))
    end
  end
end
