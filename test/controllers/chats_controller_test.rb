# test/controllers/chats_controller_test.rb
require "test_helper"

class ChatsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
    @agent = Daan::AgentRegistry.find("chief_of_staff")
  end

  test "GET /chat shows the chat interface with agents in sidebar" do
    get chat_path
    assert_response :success
    assert_select "[data-testid='sidebar']"
    assert_select "[data-testid='agent-item']", count: 2
  end

  test "GET /chat/agents/:agent_name shows the agent's conversation" do
    chat = Chat.create!(agent_name: "chief_of_staff")
    chat.messages.create!(role: "user", content: "Hello")

    get agent_chat_path("chief_of_staff")
    assert_response :success
    assert_select "[data-testid='message']", minimum: 1
  end

  test "POST /chat/agents/:agent_name/messages creates a user message and enqueues LlmJob" do
    assert_enqueued_with(job: LlmJob) do
      post agent_messages_path("chief_of_staff"),
           params: { message: { content: "Hello CoS" } }
    end

    assert_response :redirect
    assert_equal "user", Message.last.role
    assert_equal "Hello CoS", Message.last.content
  end

  test "POST creates a new chat if none exists for this agent" do
    Chat.where(agent_name: "chief_of_staff").destroy_all # clear hello_cos fixture
    assert_difference "Chat.count", 1 do
      post agent_messages_path("chief_of_staff"),
           params: { message: { content: "First message" } }
    end
  end

  test "returns 404 for unknown agent name" do
    get agent_chat_path("nobody")
    assert_response :not_found
  end
end
