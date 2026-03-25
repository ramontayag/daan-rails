require "test_helper"

class ChatDocumentPanelComponentTest < ActiveSupport::TestCase
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

  test "always renders div#chat_document_panel for broadcast targeting" do
    render_inline(ChatDocumentPanelComponent.new(chat: @chat, show_docs: false))
    assert_includes rendered_content, 'id="chat_document_panel"'
  end

  test "hidden when show_docs is false, even with documents" do
    Document.create!(title: "My Plan", body: "# Plan", chat: @chat)
    render_inline(ChatDocumentPanelComponent.new(chat: @chat, show_docs: false))
    assert_includes rendered_content, "hidden"
    assert_not_includes rendered_content, "My Plan"
  end

  test "hidden when show_docs is true but no documents exist" do
    render_inline(ChatDocumentPanelComponent.new(chat: @chat, show_docs: true))
    assert_includes rendered_content, "hidden"
  end

  test "visible with document titles when show_docs is true and documents exist" do
    Document.create!(title: "Shaping Doc", body: "# Shape", chat: @chat)
    Document.create!(title: "Slice 1 Plan", body: "# Slice", chat: @chat)
    render_inline(ChatDocumentPanelComponent.new(chat: @chat, show_docs: true))
    assert_not_includes rendered_content, "hidden"
    assert_includes rendered_content, "Shaping Doc"
    assert_includes rendered_content, "Slice 1 Plan"
  end
end
