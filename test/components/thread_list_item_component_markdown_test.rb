require "test_helper"

class ThreadListItemComponentMarkdownTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  setup do
    @chat = Chat.create!(agent_name: "chief_of_staff")
  end

  test "renders markdown bold in preview text" do
    @chat.messages.create!(role: "user", content: "This is **bold** text")
    render_inline(ThreadListItemComponent.new(chat: @chat))
    assert_includes rendered_content, "<strong>bold</strong>"
  end

  test "renders markdown italic in preview text" do
    @chat.messages.create!(role: "user", content: "This is *italic* text")
    render_inline(ThreadListItemComponent.new(chat: @chat))
    assert_includes rendered_content, "<em>italic</em>"
  end

  test "renders markdown code in preview text" do
    @chat.messages.create!(role: "user", content: "Use `code` here")
    render_inline(ThreadListItemComponent.new(chat: @chat))
    assert_includes rendered_content, "<code>code</code>"
  end

  test "renders markdown links in preview text" do
    @chat.messages.create!(role: "user", content: "Check [this](https://example.com)")
    render_inline(ThreadListItemComponent.new(chat: @chat))
    assert_includes rendered_content, '<a href="https://example.com"'
    assert_includes rendered_content, ">this</a>"
  end

  test "truncates long markdown content to 150 characters" do
    long_text = "A" * 200
    @chat.messages.create!(role: "user", content: long_text)
    render_inline(ThreadListItemComponent.new(chat: @chat))
    # Should be truncated - verify the actual content is shorter
    assert_not_includes rendered_content, "A" * 200
  end

  test "preserves markdown when content is shorter than 150 chars" do
    content = "This is **important** (40 chars)"
    @chat.messages.create!(role: "user", content: content)
    render_inline(ThreadListItemComponent.new(chat: @chat))
    assert_includes rendered_content, "<strong>important</strong>"
  end

  test "renders fenced code blocks in preview" do
    content = "```ruby\ncode = true\n```"
    @chat.messages.create!(role: "user", content: content)
    render_inline(ThreadListItemComponent.new(chat: @chat))
    assert_includes rendered_content, "<pre>"
    assert_includes rendered_content, "<code"
  end

  test "renders unordered lists in preview" do
    content = "- Item 1\n- Item 2\n- Item 3"
    @chat.messages.create!(role: "user", content: content)
    render_inline(ThreadListItemComponent.new(chat: @chat))
    assert_includes rendered_content, "<li>"
    assert_includes rendered_content, "Item 1"
  end

  test "escapes HTML in raw markdown to prevent XSS" do
    # Markdown should escape HTML tags not recognized as markdown
    content = "Text with <script>alert('xss')</script> in it"
    @chat.messages.create!(role: "user", content: content)
    render_inline(ThreadListItemComponent.new(chat: @chat))
    # Redcarpet with filter_html: true should escape script tags
    assert_not_includes rendered_content, "<script>"
  end

  test "line_clamp_2 class limits preview to 2 lines" do
    @chat.messages.create!(role: "user", content: "Test message")
    render_inline(ThreadListItemComponent.new(chat: @chat))
    assert_includes rendered_content, "line-clamp-2"
  end
end
