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
    assert_select "[data-testid='agent-item']", count: 4
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

  test "GET /chat/agents/:name with perspective param responds successfully" do
    get chat_agent_path("chief_of_staff"), params: { perspective: "engineering_manager" }
    assert_response :success
  end

  test "GET /chat/agents/:name with unknown perspective returns 404" do
    get chat_agent_path("chief_of_staff"), params: { perspective: "ghost" }
    assert_response :not_found
  end

  test "agent links carry perspective param in response" do
    parent = Chat.create!(agent_name: "chief_of_staff")
    Chat.create!(agent_name: "engineering_manager", parent_chat: parent)
    get chat_agent_path("chief_of_staff"), params: { perspective: "engineering_manager" }
    assert_select "a[href*='perspective=engineering_manager']"
  end

  test "non-me perspective shows human plus all agents except the perspective agent" do
    get chat_agent_path("engineering_manager"), params: { perspective: "engineering_manager" }
    assert_response :success
    assert_select "[data-testid='agent-item']", count: 4
  end
end
