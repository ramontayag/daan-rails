require "test_helper"

class Daan::Core::Chats::InjectWorkspaceOrientationTest < ActiveSupport::TestCase
  setup do
    @agent = Daan::Core::Agent.new(
      name: "developer",
      workspace: Daan::Core::Workspace.new(Dir.mktmpdir)
    )
    Daan::Core::AgentRegistry.register(@agent)
    @chat = Chat.create!(agent_name: "developer")
  end

  test "creates invisible user message with workspace warning" do
    Daan::Core::Chats::InjectWorkspaceOrientation.call(@chat, @agent.workspace)

    message = @chat.messages.where(role: "user", visible: false).last
    assert message, "Should create an invisible user message"
    assert_includes message.content, Daan::Core::SystemTag::PREFIX
    assert_includes message.content, "Workspace was used by another chat"
  end
end
