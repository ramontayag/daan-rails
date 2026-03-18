require "test_helper"

class ChatStepPanelComponentTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  setup do
    Daan::AgentRegistry.register(
      Daan::Agent.new(
        name: "developer", display_name: "Developer",
        model_name: "claude-sonnet-4-20250514",
        system_prompt: "You code.", max_turns: 10
      )
    )
    @chat = Chat.create!(agent_name: "developer")
  end

  test "always renders div#chat_step_panel for broadcast targeting" do
    render_inline(ChatStepPanelComponent.new(chat: @chat, show_tasks: false))
    assert_includes rendered_content, 'id="chat_step_panel"'
  end

  test "hidden when show_tasks is false, even with steps" do
    ChatStep.create!(chat: @chat, title: "Write tests", position: 1)
    render_inline(ChatStepPanelComponent.new(chat: @chat, show_tasks: false))
    assert_includes rendered_content, "hidden"
    assert_not_includes rendered_content, "Write tests"
  end

  test "hidden when show_tasks is true but no steps exist" do
    render_inline(ChatStepPanelComponent.new(chat: @chat, show_tasks: true))
    assert_includes rendered_content, "hidden"
  end

  test "visible with step content when show_tasks is true and steps exist" do
    ChatStep.create!(chat: @chat, title: "Write tests", position: 1)
    ChatStep.create!(chat: @chat, title: "Implement", position: 2)
    render_inline(ChatStepPanelComponent.new(chat: @chat, show_tasks: true))
    assert_not_includes rendered_content, "hidden"
    assert_includes rendered_content, "Write tests"
    assert_includes rendered_content, "Implement"
  end
end
