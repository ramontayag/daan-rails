require "test_helper"

class MessageComponentTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  test "user message is right-aligned with blue background" do
    render_inline(MessageComponent.new(role: "user", body: "Hello"))
    assert_includes rendered_content, "data-testid=\"message\""
    assert_includes rendered_content, "data-role=\"user\""
    assert_includes rendered_content, "text-right"
    assert_includes rendered_content, "bg-blue-500"
    assert_includes rendered_content, "Hello"
  end

  test "assistant message is left-aligned with gray background" do
    render_inline(MessageComponent.new(role: "assistant", body: "Hi there"))
    assert_includes rendered_content, "data-testid=\"message\""
    assert_includes rendered_content, "data-role=\"assistant\""
    assert_includes rendered_content, "text-left"
    assert_includes rendered_content, "bg-gray-200"
    assert_includes rendered_content, "Hi there"
  end

  test "renders with dom_id when provided" do
    render_inline(MessageComponent.new(role: "user", body: "Hello", dom_id: "message_42"))
    assert_includes rendered_content, "id=\"message_42\""
  end
end
