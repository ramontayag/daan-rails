require "test_helper"

# Verifies the delegation chain: human → CoS → EM → reports back up → CoS replies.
# Pure integration test (no browser) so VCR cassettes work across the entire
# job chain in the same thread.
class DelegationChainTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    Chat.destroy_all
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
    @em_workspace = Rails.root.join("tmp", "workspaces", "engineering_manager")
    FileUtils.mkdir_p(@em_workspace)
  end

  teardown do
    FileUtils.rm_f(@em_workspace.join("chain_test.txt"))
  end

  test "human task flows down CoS → EM and results report back up" do
    cos = Daan::AgentRegistry.find("chief_of_staff")

    VCR.use_cassette("delegation_chain/full_chain") do
      post chat_agent_threads_path(cos),
           params: { message: { content: 'Write "chain test passed" to chain_test.txt and summarise it for me' } }

      # Process jobs wave by wave so each completes before the next starts.
      # perform_enqueued_jobs without a block drains the current queue without
      # making subsequent perform_later calls inline — preventing nested execution
      # that would hit AASM InvalidTransition errors.
      10.times do
        break if queue_adapter.enqueued_jobs.empty?
        perform_enqueued_jobs(only: LlmJob)
      end
    end

    assert_response :redirect
    cos_chat = Chat.find_by(agent_name: "chief_of_staff")
    assert_not_nil cos_chat

    # CoS delegated to EM
    em_chat = Chat.find_by(agent_name: "engineering_manager", parent_chat: cos_chat)
    assert_not_nil em_chat, "Expected EM sub-chat created by CoS delegation"

    # EM completed the work
    assert em_chat.reload.completed?, "Expected EM chat to complete"
    assert File.exist?(@em_workspace.join("chain_test.txt")), "Expected EM to write chain_test.txt"
    assert_equal "chain test passed", File.read(@em_workspace.join("chain_test.txt")).strip

    # Results propagated back: CoS chat completed with a reply
    assert cos_chat.reload.completed?, "Expected CoS chat to complete after full chain"
    assert cos_chat.messages.where(role: "assistant").exists?, "Expected CoS to have replied"
  end
end
