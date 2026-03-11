require "test_helper"

class ChatFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    Chat.destroy_all
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
      post chat_agent_threads_path(agent), params: { message: { content: "Hello CoS!" } }
    end

    assert_response :redirect
    chat = Chat.where(agent_name: "chief_of_staff").last
    assert_equal 1, chat.messages.where(role: "user").count
    assert_equal "Hello CoS!", chat.messages.where(role: "user").first.content

    follow_redirect!
    assert_response :success
    assert_select "[data-testid='message']", minimum: 1
  end

  test "full flow with LLM response: assistant message saved and chat completed" do
    agent = Daan::AgentRegistry.find("chief_of_staff")

    VCR.use_cassette("llm_job/chief_of_staff_hello") do
      perform_enqueued_jobs do
        post chat_agent_threads_path(agent), params: { message: { content: "Say exactly: hello" } }
      end
    end

    chat = Chat.where(agent_name: "chief_of_staff").last
    assert chat.completed?
    assert chat.messages.where(role: "assistant").exists?

    follow_redirect!
    assert_response :success
    assert_select "[data-role='user']", 1
    assert_select "[data-role='assistant']", 1
  end

  test "system messages are not rendered in the thread view" do
    agent = Daan::AgentRegistry.find("chief_of_staff")
    chat = Chat.create!(agent_name: agent.name)
    chat.messages.create!(role: "user", content: "Hello")
    chat.messages.create!(role: "system", content: "You are the Chief of Staff...")
    chat.messages.create!(role: "assistant", content: "Hi there!")

    get chat_thread_path(chat)
    assert_response :success
    assert_select "[data-testid='message']", 2  # user + assistant only
    assert_select "[data-role='user']", 1
    assert_select "[data-role='assistant']", 1
    assert_select "[data-role='system']", 0
  end
end
