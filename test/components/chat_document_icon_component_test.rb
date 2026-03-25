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
    render_inline(ChatDocumentIconComponent.new(chat: @chat))
    assert_includes rendered_content, "chat_documents_icon_#{@chat.id}"
  end

  test "renders no button when no documents exist" do
    render_inline(ChatDocumentIconComponent.new(chat: @chat))
    assert_not_includes rendered_content, "cost-breakdown"
  end

  test "renders button with count when documents exist" do
    Document.create!(title: "Plan A", body: "# A", chat: @chat)
    Document.create!(title: "Plan B", body: "# B", chat: @chat)
    render_inline(ChatDocumentIconComponent.new(chat: @chat))
    assert_includes rendered_content, "chat_documents_count_#{@chat.id}"
    assert_includes rendered_content, "2"
  end

  test "dropdown contains document titles" do
    Document.create!(title: "Plan A", body: "# A", chat: @chat)
    Document.create!(title: "Plan B", body: "# B", chat: @chat)
    render_inline(ChatDocumentIconComponent.new(chat: @chat))
    assert_includes rendered_content, "Plan A"
    assert_includes rendered_content, "Plan B"
  end

  test "dropdown list has stable id for streaming" do
    Document.create!(title: "Plan A", body: "# A", chat: @chat)
    render_inline(ChatDocumentIconComponent.new(chat: @chat))
    assert_includes rendered_content, "chat_documents_list_#{@chat.id}"
  end

  test "each document row has stable id for update targeting" do
    doc = Document.create!(title: "Plan A", body: "# A", chat: @chat)
    render_inline(ChatDocumentIconComponent.new(chat: @chat))
    assert_includes rendered_content, "chat_document_#{doc.id}"
  end

  test "document titles link to their show page" do
    doc = Document.create!(title: "Plan A", body: "# A", chat: @chat)
    render_inline(ChatDocumentIconComponent.new(chat: @chat))
    assert_includes rendered_content, "/documents/#{doc.id}"
  end
end
