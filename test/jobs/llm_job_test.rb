# test/jobs/llm_job_test.rb
require "test_helper"

class LlmJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup do
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
    @chat = Chat.create!(agent_name: "chief_of_staff")
    @chat.messages.create!(role: "user", content: "Say exactly: hello")
  end

  test "golden path: enqueues, calls LLM, saves response, completes" do
    VCR.use_cassette("llm_job/chief_of_staff_hello") do
      LlmJob.perform_now(@chat)
    end

    @chat.reload
    assert @chat.completed?
    assert_equal 1, @chat.step_count
    assert @chat.messages.where(role: "assistant").exists?
  end

  test "developer: writes a file using the Write tool" do
    workspace = Rails.root.join("tmp", "workspaces", "developer")
    FileUtils.mkdir_p(workspace)

    chat = Chat.create!(agent_name: "developer")
    chat.messages.create!(role: "user", content: 'Write "test content" to test.txt')

    VCR.use_cassette("llm_job/developer_write_file") do
      # step re-enqueues when tool calls are returned; run all enqueued jobs
      perform_enqueued_jobs { LlmJob.perform_now(chat) }
    end

    chat.reload
    assert chat.completed?
    assert chat.messages.joins(:tool_calls).exists?
    assert File.exist?(workspace.join("test.txt"))
  ensure
    FileUtils.rm_rf(workspace.join("test.txt"))
  end

  test "fails chat gracefully when ConversationRunner raises" do
    Daan::ConversationRunner.stub(:call, ->(_) { raise "LLM exploded" }) do
      assert_raises(RuntimeError) do
        LlmJob.perform_now(@chat)
      end
    end

    @chat.reload
    assert @chat.failed?, "Expected chat to be in failed state, got #{@chat.task_status}"
  end
end
