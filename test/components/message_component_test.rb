require "test_helper"

class MessageComponentTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  test "renders message with testid and role" do
    render_inline(MessageComponent.new(role: "user", body: "Hello"))
    assert_includes rendered_content, "data-testid=\"message\""
    assert_includes rendered_content, "data-role=\"user\""
    assert_includes rendered_content, "Hello"
  end

  test "renders sender name when provided" do
    render_inline(MessageComponent.new(role: "user", body: "Hello", sender_name: "User"))
    assert_includes rendered_content, "User"
  end

  test "omits sender name element when not provided" do
    render_inline(MessageComponent.new(role: "assistant", body: "Hi"))
    assert_not_includes rendered_content, "mb-0.5"
  end

  test "renders with dom_id when provided" do
    render_inline(MessageComponent.new(role: "user", body: "Hello", dom_id: "message_42"))
    assert_includes rendered_content, "id=\"message_42\""
  end

  test "renders markdown as HTML" do
    render_inline(MessageComponent.new(role: "assistant", body: "**bold** and `code`"))
    assert_includes rendered_content, "<strong>bold</strong>"
    assert_includes rendered_content, "<code>code</code>"
  end

  test "renders fenced code blocks" do
    render_inline(MessageComponent.new(role: "assistant", body: "```\nputs 'hello'\n```"))
    assert_includes rendered_content, "<code>"
  end

  test "applies prose class" do
    render_inline(MessageComponent.new(role: "assistant", body: "Hi"))
    assert_includes rendered_content, "prose"
  end
end
