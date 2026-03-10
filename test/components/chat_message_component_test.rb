require "test_helper"

class ChatMessageComponentTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  setup do
    @chat = Chat.create!(agent_name: "chief_of_staff")
  end

  test "renders an assistant message" do
    message = @chat.messages.create!(role: "assistant", content: "Hello there")
    render_inline(ChatMessageComponent.new(message: message))
    assert_includes rendered_content, "Hello there"
    assert_includes rendered_content, "data-role=\"assistant\""
  end

  test "renders a user message" do
    message = @chat.messages.create!(role: "user", content: "Hi!")
    render_inline(ChatMessageComponent.new(message: message))
    assert_includes rendered_content, "Hi!"
    assert_includes rendered_content, "data-role=\"user\""
  end

  test "does not render a tool message" do
    assistant = @chat.messages.create!(role: "assistant", content: nil)
    tool_call = ToolCall.create!(message: assistant, tool_call_id: "tc_skip", name: "noop", arguments: {})
    message = @chat.messages.create!(role: "tool", content: "result", tool_call_id: tool_call.id)
    render_inline(ChatMessageComponent.new(message: message))
    assert_equal "", rendered_content.strip
  end

  test "does not render a system message" do
    message = @chat.messages.create!(role: "system", content: "You are...")
    render_inline(ChatMessageComponent.new(message: message))
    assert_equal "", rendered_content.strip
  end

  test "renders tool calls for an assistant message with tool calls" do
    message = @chat.messages.create!(role: "assistant", content: nil)
    ToolCall.create!(message: message, tool_call_id: "tc_001", name: "read_file",
                     arguments: { "path" => "foo.txt" })
    render_inline(ChatMessageComponent.new(message: message))
    assert_includes rendered_content, "read_file"
    assert_includes rendered_content, "data-testid=\"tool-call\""
  end

  test "passes pre-loaded result to ToolCallComponent" do
    message = @chat.messages.create!(role: "assistant", content: nil)
    tool_call = ToolCall.create!(message: message, tool_call_id: "tc_002", name: "write_file",
                                 arguments: { "path" => "out.txt" })
    results = { tool_call.id => "file written" }
    render_inline(ChatMessageComponent.new(message: message, results: results))
    assert_includes rendered_content, "file written"
  end

  test "flips alignment when viewer_is_agent is true" do
    message = @chat.messages.create!(role: "assistant", content: "Done.")
    render_inline(ChatMessageComponent.new(message: message, viewer_is_agent: true))
    assert_includes rendered_content, "text-right"
    assert_includes rendered_content, "bg-blue-500"
  end

  test "hides tool calls when hide_tools is true and message has no text content" do
    message = @chat.messages.create!(role: "assistant", content: nil)
    ToolCall.create!(message: message, tool_call_id: "tc_hide_01", name: "read", arguments: {})
    render_inline(ChatMessageComponent.new(message: message, hide_tools: true))
    assert_not_includes rendered_content, "data-testid=\"tool-call\""
  end

  test "shows tool calls by default" do
    message = @chat.messages.create!(role: "assistant", content: nil)
    ToolCall.create!(message: message, tool_call_id: "tc_show_01", name: "read", arguments: {})
    render_inline(ChatMessageComponent.new(message: message))
    assert_includes rendered_content, "data-testid=\"tool-call\""
  end

  test "still renders text content when hide_tools is true and message has both tool calls and content" do
    message = @chat.messages.create!(role: "assistant", content: "Here is the result.")
    ToolCall.create!(message: message, tool_call_id: "tc_mixed_01", name: "read", arguments: {})
    render_inline(ChatMessageComponent.new(message: message, hide_tools: true))
    assert_not_includes rendered_content, "data-testid=\"tool-call\""
    assert_includes rendered_content, "Here is the result."
  end
end
