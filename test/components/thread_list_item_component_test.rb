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

  test "truncates long preview text" do
    @chat.messages.create!(role: "user", content: "A" * 100)
    render_inline(ThreadListItemComponent.new(chat: @chat))
    assert_includes rendered_content, "..."
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
end
