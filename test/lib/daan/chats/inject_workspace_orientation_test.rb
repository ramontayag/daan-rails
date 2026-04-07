require "test_helper"

class Daan::Chats::InjectWorkspaceOrientationTest < ActiveSupport::TestCase
  setup do
    @agent = Daan::Agent.new(
      name: "developer", display_name: "Dev",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You are a developer.", max_steps: 10,
      workspace: Daan::Workspace.new(Dir.mktmpdir)
    )
    Daan::AgentRegistry.register(@agent)
    @chat = Chat.create!(agent_name: "developer")
  end

  test "creates invisible user message with workspace warning" do
    Daan::Chats::InjectWorkspaceOrientation.call(@chat, @agent.workspace)

    message = @chat.messages.where(role: "user", visible: false).last
    assert message, "Should create an invisible user message"
    assert_includes message.content, Daan::SystemTag::PREFIX
    assert_includes message.content, "Workspace was used by another chat"
  end
end
