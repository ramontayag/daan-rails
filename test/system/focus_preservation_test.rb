require "application_system_test_case"

class FocusPreservationTest < ApplicationSystemTestCase
  setup do
    Chat.destroy_all
    Daan::Core::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
    @agent = Daan::Core::AgentRegistry.find("chief_of_staff")
    @chat = Chat.create!(agent_name: @agent.name)
    @chat.messages.create!(role: "user", content: "Hello", visible: true)
    @chat.messages.create!(role: "assistant", content: "Hi there", visible: true)

    # Prevent LlmJob from hitting the real API
    ActiveJob::Base.queue_adapter = :test
  end

  teardown do
    ActiveJob::Base.queue_adapter = :test
  end

  test "focus stays on thread panel textarea through send-and-reply cycle" do
    visit chat_thread_path(@chat)

    # Send a message
    thread_input = find("[data-testid='thread-panel'] textarea[data-testid='message-input']")
    thread_input.fill_in with: "test message"
    thread_input.send_keys(:return)

    assert_focused_on_thread_panel_input

    # Agent starts typing
    Turbo::StreamsChannel.broadcast_replace_to(
      "chat_#{@chat.id}",
      target: "agent_activity_indicator",
      html: '<div id="agent_activity_indicator"><p class="text-sm text-gray-400 italic px-4 py-1">Typing...</p></div>'
    )
    assert_text "Typing..."

    assert_focused_on_thread_panel_input

    # Agent replies
    @chat.messages.create!(role: "assistant", content: "Got it!", visible: true)
    Turbo::StreamsChannel.broadcast_append_to(
      "chat_#{@chat.id}",
      target: "messages",
      html: '<div class="p-2" data-role="assistant">Got it!</div>'
    )
    assert_text "Got it!"

    assert_focused_on_thread_panel_input
  end

  private

  def assert_focused_on_thread_panel_input
    assert_selector "[data-testid='thread-panel'] textarea[data-testid='message-input']:focus"
  end
end
