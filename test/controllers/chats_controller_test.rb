# test/controllers/chats_controller_test.rb
require "test_helper"

class ChatsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Chat.destroy_all
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
  end

  test "GET /chat shows sidebar with agents" do
    get chat_path
    assert_response :success
    assert_select "[data-testid='sidebar']"
    assert_select "[data-testid='agent-item']", count: 3
  end

  test "GET /chat/agents/:agent_name shows thread list" do
    Chat.create!(agent_name: "chief_of_staff")
    Chat.create!(agent_name: "chief_of_staff")
    get chat_agent_path("chief_of_staff")
    assert_response :success
    assert_select "[data-testid='thread-list-item']", count: 2
  end

  test "returns 404 for unknown agent" do
    get chat_agent_path("nobody")
    assert_response :not_found
  end
end
