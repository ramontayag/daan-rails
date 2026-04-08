require "test_helper"

class ChatStepListComponentTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  setup do
    Daan::Core::AgentRegistry.register(
      Daan::Core::Agent.new(
        name: "developer", display_name: "Developer",
        model_name: "claude-sonnet-4-20250514",
        system_prompt: "You code.", max_steps: 10
      )
    )
    @chat = Chat.create!(agent_name: "developer")
  end

  test "renders steps as a checklist" do
    ChatStep.create!(chat: @chat, title: "Clone repo", position: 1, status: "completed")
    ChatStep.create!(chat: @chat, title: "Write tests", position: 2, status: "in_progress")
    ChatStep.create!(chat: @chat, title: "Implement", position: 3)

    render_inline(ChatStepListComponent.new(chat: @chat))

    assert_includes rendered_content, "Clone repo"
    assert_includes rendered_content, "Write tests"
    assert_includes rendered_content, "Implement"
  end

  test "renders nothing when no steps exist" do
    render_inline(ChatStepListComponent.new(chat: @chat))

    assert_equal "", rendered_content.strip
  end
end
