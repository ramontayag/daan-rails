require "test_helper"

class ChatDocumentIconComponentTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  setup do
    Daan::AgentRegistry.register(
      Daan::Agent.new(
        name: "developer", display_name: "Developer",
        model_name: "claude-sonnet-4-20250514",
        system_prompt: "You code.", max_steps: 10
      )
    )
    @chat = Chat.create!(agent_name: "developer")
  end

  test "always renders div with stable id for broadcast targeting" do
    render_inline(ChatDocumentIconComponent.new(chat: @chat, show_docs: false))
    assert_includes rendered_content, "chat_documents_icon_#{@chat.id}"
  end

  test "renders no link when no documents exist" do
    render_inline(ChatDocumentIconComponent.new(chat: @chat, show_docs: false))
    assert_not_includes rendered_content, "Show documents"
  end

  test "renders icon link with count when documents exist" do
    Document.create!(title: "Plan A", body: "# A", chat: @chat)
    Document.create!(title: "Plan B", body: "# B", chat: @chat)
    render_inline(ChatDocumentIconComponent.new(chat: @chat, show_docs: false))
    assert_includes rendered_content, "Show documents"
    assert_includes rendered_content, "2"
  end

  test "link title reflects current show_docs state" do
    Document.create!(title: "Plan", body: "# P", chat: @chat)
    render_inline(ChatDocumentIconComponent.new(chat: @chat, show_docs: true))
    assert_includes rendered_content, "Hide documents"
  end
end
