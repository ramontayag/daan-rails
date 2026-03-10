require "test_helper"

# Full delegation chain smoke test:
# Human → CoS → EM → Developer → reports back up → CoS replies.
# Also verifies that perspective switching shows the correct conversation
# partners in the sidebar after the chain completes.
class DelegationChainTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    Chat.destroy_all
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
    @workspace = Rails.root.join("tmp", "workspaces", "developer")
    FileUtils.mkdir_p(@workspace)
  end

  teardown do
    FileUtils.rm_f(@workspace.join("chain_test.txt"))
  end

  test "human task flows down CoS → EM → Developer and results report back up" do
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

    # EM delegated to Developer
    dev_chat = Chat.find_by(agent_name: "developer", parent_chat: em_chat)
    assert_not_nil dev_chat, "Expected Developer sub-chat created by EM delegation"

    # Developer did the work
    assert File.exist?(@workspace.join("chain_test.txt")), "Expected developer to write chain_test.txt"
    assert_equal "chain test passed", File.read(@workspace.join("chain_test.txt")).strip

    # Results propagated back: CoS chat completed
    assert cos_chat.reload.completed?, "Expected CoS chat to complete after full chain"

    # CoS has a final assistant reply synthesising the result
    assert cos_chat.messages.where(role: "assistant").exists?, "Expected CoS to have replied to the human"

    # --- Perspective switching ---

    # CoS perspective: sidebar shows only EM (direct report)
    get chat_path, params: { perspective: "chief_of_staff" }
    assert_response :success
    assert_select "[data-testid='agent-item']", count: 1
    assert_select "[data-testid='agent-item']", text: /Engineering Manager/

    # EM perspective: sidebar shows CoS (above) and Developer (below)
    get chat_path, params: { perspective: "engineering_manager" }
    assert_response :success
    assert_select "[data-testid='agent-item']", count: 2

    # EM perspective thread: compose bar is read-only
    get chat_thread_path(em_chat), params: { perspective: "engineering_manager" }
    assert_response :success
    assert_select "[data-testid='compose-bar']"
    assert_includes response.body, "read-only"
  end
end
