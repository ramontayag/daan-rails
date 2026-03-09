# test/components/tool_call_component_test.rb
require "test_helper"

class ToolCallComponentTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  setup do
    @chat = Chat.create!(agent_name: "chief_of_staff")
    @message = @chat.messages.create!(role: "assistant", content: nil)
    @tool_call = ToolCall.create!(
      message: @message,
      tool_call_id: "tc_001",
      name: "read",
      arguments: { "path" => "hello.txt" }
    )
  end

  test "shows tool name" do
    render_inline(ToolCallComponent.new(tool_call: @tool_call))
    assert_includes rendered_content, "read"
  end

  test "shows arguments" do
    render_inline(ToolCallComponent.new(tool_call: @tool_call))
    assert_includes rendered_content, "hello.txt"
  end

  test "shows result when a tool result message exists" do
    @chat.messages.create!(role: "tool", content: "file contents here",
                           tool_call_id: @tool_call.id)
    render_inline(ToolCallComponent.new(tool_call: @tool_call))
    assert_includes rendered_content, "file contents here"
  end

  test "shows running state when no result yet" do
    render_inline(ToolCallComponent.new(tool_call: @tool_call))
    assert_includes rendered_content, "running"
  end
end
