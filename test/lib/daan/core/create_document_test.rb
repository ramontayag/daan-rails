# test/lib/daan/core/create_document_test.rb
require "test_helper"

class Daan::Core::CreateDocumentTest < ActiveSupport::TestCase
  setup do
    @agent = build_agent
    Daan::Core::AgentRegistry.register(@agent)
    @chat = Chat.create!(agent_name: @agent.name)
    @tool = Daan::Core::CreateDocument.new(chat: @chat)
  end

  test "creates a document for the chat" do
    assert_difference -> { @chat.documents.count }, 1 do
      @tool.execute(title: "My Plan", body: "# My Plan\n\nDetails here.")
    end
  end

  test "saves title and body" do
    @tool.execute(title: "My Plan", body: "# My Plan\n\nDetails here.")
    doc = @chat.documents.last
    assert_equal "My Plan", doc.title
    assert_equal "# My Plan\n\nDetails here.", doc.body
  end

  test "returns the document id and a markdown link" do
    result = @tool.execute(title: "My Plan", body: "# My Plan")
    doc = @chat.documents.last
    assert_includes result, doc.id.to_s
    assert_includes result, "/documents/#{doc.id}"
    assert_includes result, "[My Plan]"
  end
end
