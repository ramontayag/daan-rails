require "test_helper"

class ThreadListItemComponentTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  setup do
    @chat = Chat.create!(agent_name: "chief_of_staff")
  end

  test "shows preview text from first user message" do
    @chat.messages.create!(role: "user", content: "Write me a report")
    render_inline(ThreadListItemComponent.new(chat: @chat))
    assert_includes rendered_content, "Write me a report"
  end

  test "shows full preview text without truncation" do
    long_content = "A" * 100
    @chat.messages.create!(role: "user", content: long_content)
    render_inline(ThreadListItemComponent.new(chat: @chat))
    assert_includes rendered_content, long_content
  end

  test "shows (empty) when no user message" do
    render_inline(ThreadListItemComponent.new(chat: @chat))
    assert_includes rendered_content, "(empty)"
  end

  test "reply count excludes the opening message" do
    @chat.messages.create!(role: "user", content: "Hello")
    @chat.messages.create!(role: "assistant", content: "Hi!")
    @chat.messages.create!(role: "assistant", content: "How can I help?")
    render_inline(ThreadListItemComponent.new(chat: @chat))
    assert_includes rendered_content, "2 replies"
  end

  test "shows 0 replies for a thread with only the opening message" do
    @chat.messages.create!(role: "user", content: "Hello")
    render_inline(ThreadListItemComponent.new(chat: @chat))
    assert_includes rendered_content, "0 replies"
  end

  test "uses singular reply for one reply" do
    @chat.messages.create!(role: "user", content: "Hello")
    @chat.messages.create!(role: "assistant", content: "Hi!")
    render_inline(ThreadListItemComponent.new(chat: @chat))
    assert_includes rendered_content, "1 reply"
    assert_not_includes rendered_content, "1 replies"
  end

  test "link navigates directly to thread url (no turbo frame target)" do
    render_inline(ThreadListItemComponent.new(chat: @chat))
    assert_not_includes rendered_content, "data-turbo-frame"
    assert_includes rendered_content, "href=\"/chat/threads/#{@chat.id}\""
  end

  test "shows selected style when open" do
    render_inline(ThreadListItemComponent.new(chat: @chat, open: true))
    assert_includes rendered_content, "bg-blue-50"
    assert_not_includes rendered_content, "hover:bg-gray-50"
  end

  test "shows hover style when not open" do
    render_inline(ThreadListItemComponent.new(chat: @chat))
    assert_includes rendered_content, "hover:bg-gray-50"
    assert_not_includes rendered_content, "bg-blue-50"
  end

  # Markdown rendering tests
  test "renders bold markdown in preview text" do
    @chat.messages.create!(role: "user", content: "This is **bold** text")
    render_inline(ThreadListItemComponent.new(chat: @chat))
    assert_includes rendered_content, "<strong>bold</strong>"
    assert_not_includes rendered_content, "**bold**"
  end

  test "renders italic markdown in preview text" do
    @chat.messages.create!(role: "user", content: "This is *italic* text")
    render_inline(ThreadListItemComponent.new(chat: @chat))
    assert_includes rendered_content, "<em>italic</em>"
    assert_not_includes rendered_content, "*italic*"
  end

  test "renders inline code in preview text" do
    @chat.messages.create!(role: "user", content: "Use `require` to import")
    render_inline(ThreadListItemComponent.new(chat: @chat))
    assert_includes rendered_content, "<code>require</code>"
    assert_not_includes rendered_content, "`require`"
  end

  test "renders links in preview text" do
    @chat.messages.create!(role: "user", content: "Check [this link](https://example.com)")
    render_inline(ThreadListItemComponent.new(chat: @chat))
    assert_includes rendered_content, '<a href="https://example.com">this link</a>'
    assert_not_includes rendered_content, "[this link]"
  end

  test "truncates long markdown preview at ~150 characters" do
    long_text = "This is a very long message that should be truncated " * 5
    @chat.messages.create!(role: "user", content: long_text)
    render_inline(ThreadListItemComponent.new(chat: @chat))
    rendered = rendered_content
    # Should contain truncation ellipsis
    assert_includes rendered, "…"
    # Should not contain the full text
    assert_not_includes rendered, long_text
  end

  test "preserves markdown formatting when truncating" do
    text = "Here is some **bold text** that is in the middle of a much longer message that should eventually be truncated"
    @chat.messages.create!(role: "user", content: text)
    render_inline(ThreadListItemComponent.new(chat: @chat))
    # Should render the bold markdown even when truncated
    assert_includes rendered_content, "<strong>bold text</strong>"
  end

  test "renders code blocks in preview" do
    code_block = "Here's some code:\n```ruby\nputs 'hello'\n```"
    @chat.messages.create!(role: "user", content: code_block)
    render_inline(ThreadListItemComponent.new(chat: @chat))
    # Redcarpet renders code blocks as <pre><code>
    assert_includes rendered_content, "<pre><code"
    assert_includes rendered_content, "puts"
  end

  test "does not render raw markdown syntax in output" do
    @chat.messages.create!(role: "user", content: "This **should** be bold")
    render_inline(ThreadListItemComponent.new(chat: @chat))
    # Make sure the raw markdown syntax doesn't appear
    assert_not_includes rendered_content, "**should**"
  end

  # Prose styling tests
  test "applies prose styling classes to preview text" do
    @chat.messages.create!(role: "user", content: "Use `code` in preview")
    render_inline(ThreadListItemComponent.new(chat: @chat))
    # Should have prose and prose-sm classes for styling
    assert_includes rendered_content, 'class="prose prose-sm max-w-none line-clamp-2 text-gray-900"'
  end

  test "applies syntax-highlight controller for code highlighting" do
    @chat.messages.create!(role: "user", content: "```ruby\nputs 'test'\n```")
    render_inline(ThreadListItemComponent.new(chat: @chat))
    # Should have syntax-highlight data controller
    assert_includes rendered_content, 'data-controller="syntax-highlight"'
  end

  test "inline code has proper styling via prose" do
    @chat.messages.create!(role: "user", content: "Use `require` for imports")
    render_inline(ThreadListItemComponent.new(chat: @chat))
    # Prose applies styling to <code> tags - check that code is rendered
    assert_includes rendered_content, "<code>require</code>"
    # Should be wrapped in prose div for styling
    assert_includes rendered_content, "prose"
  end
end
