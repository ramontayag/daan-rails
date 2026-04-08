require "test_helper"

class ThreadPanelHeaderComponentTest < ActiveSupport::TestCase
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

  test "renders back link on mobile" do
    render_inline(ThreadPanelHeaderComponent.new(chat: @chat, show_tasks: false, hide_tools: false))
    assert_selector ".md\\:hidden a", text: "← Back"
  end

  test "renders desktop close link" do
    render_inline(ThreadPanelHeaderComponent.new(chat: @chat, show_tasks: false, hide_tools: false))
    assert_selector "a[title='Close']"
  end

  test "does not render tasks toggle when chat has no steps" do
    render_inline(ThreadPanelHeaderComponent.new(chat: @chat, show_tasks: false, hide_tools: false))
    refute_selector "a[title='Show steps']"
    refute_selector "a[title='Hide steps']"
  end

  test "renders tasks toggle when chat has steps" do
    ChatStep.create!(chat: @chat, title: "Write tests", position: 1)
    render_inline(ThreadPanelHeaderComponent.new(chat: @chat, show_tasks: false, hide_tools: false))
    assert_selector "a[title='Show steps']"
  end

  test "tasks toggle title is 'Show steps' when show_tasks is false" do
    ChatStep.create!(chat: @chat, title: "Write tests", position: 1)
    render_inline(ThreadPanelHeaderComponent.new(chat: @chat, show_tasks: false, hide_tools: false))
    assert_selector "a[title='Show steps']"
  end

  test "tasks toggle title is 'Hide steps' when show_tasks is true" do
    ChatStep.create!(chat: @chat, title: "Write tests", position: 1)
    render_inline(ThreadPanelHeaderComponent.new(chat: @chat, show_tasks: true, hide_tools: false))
    assert_selector "a[title='Hide steps']"
  end

  test "tasks toggle path includes show_tasks=1 when currently false" do
    ChatStep.create!(chat: @chat, title: "Write tests", position: 1)
    render_inline(ThreadPanelHeaderComponent.new(chat: @chat, show_tasks: false, hide_tools: false))
    assert_includes rendered_content, "show_tasks=1"
  end

  test "tasks toggle path includes show_tasks=0 when currently true" do
    ChatStep.create!(chat: @chat, title: "Write tests", position: 1)
    render_inline(ThreadPanelHeaderComponent.new(chat: @chat, show_tasks: true, hide_tools: false))
    assert_includes rendered_content, "show_tasks=0"
  end

  test "tools toggle title is 'Hide tools' when tools are visible" do
    render_inline(ThreadPanelHeaderComponent.new(chat: @chat, show_tasks: false, hide_tools: false))
    assert_selector "a[title='Hide tools']"
  end

  test "tools toggle title is 'Show tools' when tools are hidden" do
    render_inline(ThreadPanelHeaderComponent.new(chat: @chat, show_tasks: false, hide_tools: true))
    assert_selector "a[title='Show tools']"
  end

  test "tools link has prominent color when tools are visible" do
    render_inline(ThreadPanelHeaderComponent.new(chat: @chat, show_tasks: false, hide_tools: false))
    assert_includes rendered_content, "text-gray-800"
  end

  test "tools link has muted color when tools are hidden" do
    render_inline(ThreadPanelHeaderComponent.new(chat: @chat, show_tasks: false, hide_tools: true))
    assert_includes rendered_content, "text-gray-300"
  end

  test "tools toggle path includes show_tools=0 when currently visible" do
    render_inline(ThreadPanelHeaderComponent.new(chat: @chat, show_tasks: false, hide_tools: false))
    assert_includes rendered_content, "show_tools=0"
  end

  test "tools toggle path includes show_tools=1 when currently hidden" do
    render_inline(ThreadPanelHeaderComponent.new(chat: @chat, show_tasks: false, hide_tools: true))
    assert_includes rendered_content, "show_tools=1"
  end
end
