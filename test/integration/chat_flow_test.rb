require "test_helper"

class ChatFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
  end

  test "sidebar shows loaded agents" do
    get chat_path
    assert_response :success
    assert_select "[data-testid='agent-item']", minimum: 1
    assert_select "[data-testid='agent-item']", text: /Chief of Staff/
  end

  test "full flow: send message, job enqueued, message saved" do
    agent = Daan::AgentRegistry.find("chief_of_staff")

    assert_enqueued_with(job: LlmJob) do
      post agent_messages_path(agent), params: { message: { content: "Hello CoS!" } }
    end

    assert_response :redirect
    chat = Chat.where(agent_name: "chief_of_staff").last
    assert_equal 1, chat.messages.count
    assert_equal "user", chat.messages.first.role
    assert_equal "Hello CoS!", chat.messages.first.content

    follow_redirect!
    assert_response :success
    assert_select "[data-testid='message']", minimum: 1
  end
end
