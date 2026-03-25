# test/lib/daan/core/create_document_test.rb
require "test_helper"

class Daan::Core::CreateDocumentTest < ActiveSupport::TestCase
  setup do
    Daan::AgentRegistry.register(
      Daan::Agent.new(name: "chief_of_staff", display_name: "Chief of Staff",
                      model_name: "m", system_prompt: "p", max_steps: 10)
    )
    @chat = Chat.create!(agent_name: "chief_of_staff")
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

  test "returns the document id" do
    result = @tool.execute(title: "My Plan", body: "# My Plan")
    doc = @chat.documents.last
    assert_includes result, doc.id.to_s
  end
end
