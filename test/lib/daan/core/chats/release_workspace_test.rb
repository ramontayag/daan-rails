require "test_helper"

class Daan::Core::Chats::ReleaseWorkspaceTest < ActiveSupport::TestCase
  setup do
    @agent = build_agent
    Daan::Core::AgentRegistry.register(@agent)
    @chat = Chat.create!(agent_name: @agent.name)
    WorkspaceLock.acquire(chat: @chat, agent_name: @agent.name)
  end

  test "releases the lock" do
    Daan::Core::Chats::ReleaseWorkspace.call(@chat)
    other_chat = Chat.create!(agent_name: @agent.name)
    result = WorkspaceLock.acquire(chat: other_chat, agent_name: @agent.name)
    assert result.acquired?
  end

  test "is safe to call when no lock exists" do
    assert_nothing_raised do
      Daan::Core::Chats::ReleaseWorkspace.call(Chat.create!(agent_name: @agent.name))
    end
  end
end
