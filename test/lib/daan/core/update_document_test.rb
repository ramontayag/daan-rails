# test/lib/daan/core/update_document_test.rb
require "test_helper"

class Daan::Core::UpdateDocumentTest < ActiveSupport::TestCase
  setup do
    Daan::AgentRegistry.register(
      Daan::Agent.new(name: "chief_of_staff", display_name: "Chief of Staff",
                      model_name: "m", system_prompt: "p", max_steps: 10)
    )
    @chat = Chat.create!(agent_name: "chief_of_staff")
    @doc = Document.create!(title: "Old Title", body: "Old body", chat: @chat)
    @tool = Daan::Core::UpdateDocument.new(chat: @chat)
  end

  test "updates the body of the document" do
    @tool.execute(id: @doc.id, body: "New body")
    assert_equal "New body", @doc.reload.body
  end

  test "returns the document id" do
    result = @tool.execute(id: @doc.id, body: "New body")
    assert_includes result, @doc.id.to_s
  end

  test "does not change the title" do
    @tool.execute(id: @doc.id, body: "New body")
    assert_equal "Old Title", @doc.reload.title
  end

  test "returns error when document id does not exist" do
    result = @tool.execute(id: 0, body: "New body")
    assert_includes result, "No document with id=0 found"
  end

  test "does not update a document belonging to a different chat" do
    other_chat = Chat.create!(agent_name: "chief_of_staff")
    other_doc = Document.create!(title: "Other", body: "Other body", chat: other_chat)
    result = Daan::Core::UpdateDocument.new(chat: @chat).execute(id: other_doc.id, body: "Hacked")
    assert_includes result, "No document with id=#{other_doc.id} found"
    assert_equal "Other body", other_doc.reload.body
  end
end
