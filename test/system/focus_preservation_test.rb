require "application_system_test_case"

class FocusPreservationTest < ApplicationSystemTestCase
  setup do
    Chat.destroy_all
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
    @agent = Daan::AgentRegistry.find("chief_of_staff")
    @chat = Chat.create!(agent_name: @agent.name)
    @chat.messages.create!(role: "user", content: "Hello", visible: true)
    @chat.messages.create!(role: "assistant", content: "Hi there", visible: true)

    # Prevent LlmJob from hitting the real API
    ActiveJob::Base.queue_adapter = :test
  end

  teardown do
    ActiveJob::Base.queue_adapter = :test
  end

  test "focus stays on thread panel textarea after sending a message" do
    visit chat_thread_path(@chat)

    thread_input = find("[data-testid='thread-panel'] textarea[data-testid='message-input']")
    thread_input.fill_in with: "test message"
    thread_input.send_keys(:return)

    # After submission, focus should remain on the thread panel textarea
    assert_focused_on_thread_panel_input
  end

  test "focus stays on thread panel textarea after typing indicator appears" do
    visit chat_thread_path(@chat)

    thread_input = find("[data-testid='thread-panel'] textarea[data-testid='message-input']")
    thread_input.click

    assert_focused_on_thread_panel_input

    # Simulate the typing indicator broadcast
    Turbo::StreamsChannel.broadcast_replace_to(
      "chat_#{@chat.id}",
      target: "typing_indicator",
      html: '<div id="typing_indicator"><p class="text-sm text-gray-400 italic px-4 py-1">Typing...</p></div>'
    )

    assert_text "Typing..."

    assert_focused_on_thread_panel_input
  end

  test "focus stays on thread panel textarea after new message is appended" do
    visit chat_thread_path(@chat)

    thread_input = find("[data-testid='thread-panel'] textarea[data-testid='message-input']")
    thread_input.click

    assert_focused_on_thread_panel_input

    # Simulate a new message broadcast
    msg = @chat.messages.create!(role: "assistant", content: "A new reply", visible: true)
    Turbo::StreamsChannel.broadcast_append_to(
      "chat_#{@chat.id}",
      target: "messages",
      html: '<div class="p-2" data-role="assistant">A new reply</div>'
    )

    assert_text "A new reply"

    assert_focused_on_thread_panel_input
  end

  private

  def assert_focused_on_thread_panel_input
    active_testid = evaluate_script("document.activeElement?.dataset?.testid")
    assert_equal "message-input", active_testid, "Expected focus on a message-input"

    active_in_thread_panel = evaluate_script(
      "document.activeElement?.closest('[data-testid=\"thread-panel\"]') !== null"
    )
    assert active_in_thread_panel, "Expected focus on the thread panel's input, not the thread list's"
  end
end
