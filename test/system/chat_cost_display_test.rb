require "test_helper"

# Integration test: send a message, let the agent respond via VCR,
# then verify the cost (not just tokens) is displayed in the thread.
class ChatCostDisplayTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    Chat.destroy_all
    Daan::Core::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
  end

  test "chat shows dollar cost after agent responds" do
    agent = Daan::Core::AgentRegistry.find("chief_of_staff")

    VCR.use_cassette("chat_cost_display/simple_reply") do
      perform_enqueued_jobs do
        post chat_agent_threads_path(agent),
             params: { message: { content: "Say hello in one word" } }
      end
    end

    chat = Chat.where(agent_name: "chief_of_staff").last
    assert chat.completed?, "expected chat to be completed"
    assert chat.total_tokens > 0, "expected tokens to be recorded"
    assert chat.estimated_cost_usd > 0, "expected cost to be calculated from real pricing data"

    get chat_thread_path(chat)
    assert_response :success
    assert_includes response.body, "$", "expected dollar cost to be displayed in thread"
  end
end
