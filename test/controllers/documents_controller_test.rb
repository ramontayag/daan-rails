# test/controllers/documents_controller_test.rb
require "test_helper"

class DocumentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Daan::AgentRegistry.register(
      Daan::Agent.new(name: "chief_of_staff", display_name: "Chief of Staff",
                      model_name: "m", system_prompt: "p", max_steps: 10)
    )
    @chat = Chat.create!(agent_name: "chief_of_staff")
    @doc = Document.create!(title: "My Plan", body: "# Hello\n\nWorld", chat: @chat)
  end

  test "GET show returns success" do
    get document_path(@doc)
    assert_response :success
  end

  test "GET show renders document title" do
    get document_path(@doc)
    assert_select "h1", text: /My Plan/
  end

  test "GET show renders body as HTML" do
    get document_path(@doc)
    assert_select "h1", text: /Hello/
  end

  test "GET show includes mermaid script" do
    get document_path(@doc)
    assert_match "mermaid", response.body
  end

  test "GET show X button links to return_to_uri" do
    get document_path(@doc, return_to_uri: "/chat/threads/99")
    assert_select "a[href='/chat/threads/99']"
  end

  test "GET show X button links to root when no return_to_uri" do
    get document_path(@doc)
    assert_select "a[href='/']"
  end
end
