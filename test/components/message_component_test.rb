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

  test "rewrites /documents/:id links with return_to_uri and turbo frame" do
    render_inline(MessageComponent.new(
      role: "assistant",
      body: "See [the plan](/documents/42)",
      return_to_uri: "/chat/threads/1"
    ))
    assert_includes rendered_content, "href=\"/documents/42?return_to_uri=%2Fchat%2Fthreads%2F1\""
    assert_includes rendered_content, "data-turbo-frame=\"_top\""
  end

  test "does not rewrite non-document links" do
    render_inline(MessageComponent.new(
      role: "assistant",
      body: "See [Google](https://google.com)",
      return_to_uri: "/chat/threads/1"
    ))
    assert_includes rendered_content, "https://google.com"
    assert_not_includes rendered_content, "return_to_uri"
  end

  test "rewrites absolute document URLs to relative path with return_to_uri" do
    render_inline(MessageComponent.new(
      role: "assistant",
      body: "See [the plan](https://example.com/documents/42)",
      return_to_uri: "/chat/threads/1"
    ))
    assert_includes rendered_content, "href=\"/documents/42?return_to_uri=%2Fchat%2Fthreads%2F1\""
    assert_not_includes rendered_content, "example.com"
  end

  test "does not add return_to_uri when not given" do
    render_inline(MessageComponent.new(role: "assistant", body: "See [plan](/documents/42)"))
    assert_not_includes rendered_content, "return_to_uri"
  end
end
