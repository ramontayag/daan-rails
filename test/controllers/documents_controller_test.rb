# test/controllers/documents_controller_test.rb
require "test_helper"

class DocumentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @agent = build_agent
    Daan::Core::AgentRegistry.register(@agent)
    @chat = Chat.create!(agent_name: @agent.name)
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

  test "GET show strips host from return_to_uri to prevent open redirect" do
    get document_path(@doc, return_to_uri: "http://evil.com/steal")
    assert_select "a[href='/steal']"
    assert_no_match "evil.com", response.body
  end

  test "GET show.md returns raw markdown body as attachment" do
    get document_path(@doc, format: :md)
    assert_response :success
    assert_equal @doc.body, response.body
    assert_match "attachment", response.headers["Content-Disposition"]
  end

  test "GET show.md uses slugified title as filename" do
    get document_path(@doc, format: :md)
    assert_match "my-plan.md", response.headers["Content-Disposition"]
  end

  test "GET show.md sets text/markdown content type" do
    get document_path(@doc, format: :md)
    assert_match "text/markdown", response.content_type
  end
end
