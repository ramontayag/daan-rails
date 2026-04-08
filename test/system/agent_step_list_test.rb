require "test_helper"

# Verifies the agent step list feature end-to-end:
# - Agent calls CreateSteps when asked → ChatStep records are created
# - Steps appear in the thread panel HTML
class AgentStepListTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    Chat.destroy_all
    Daan::Core::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
  end

  test "agent creates a step list when asked and steps appear in the thread panel" do
    agent = Daan::Core::AgentRegistry.find("developer")

    VCR.use_cassette("agent_step_list/creates_steps") do
      perform_enqueued_jobs do
        post chat_agent_threads_path(agent),
             params: { message: { content: 'Use the CreateSteps tool to make a task list with exactly these three steps: "Say hello", "Say hi", "Say goodbye". Then reply with just "Done."' } }
      end
    end

    assert_response :redirect
    chat = Chat.where(agent_name: "developer").last
    assert chat.completed?, "expected chat to complete"
    assert_equal 3, chat.chat_steps.count
    assert_equal "Say hello", chat.chat_steps.first.title

    follow_redirect!
    assert_response :success
    assert_includes response.body, "Say hello"
    assert_includes response.body, "Say hi"
    assert_includes response.body, "Say goodbye"
  end
end
