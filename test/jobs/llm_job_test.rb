# test/jobs/llm_job_test.rb
require "test_helper"

class LlmJobTest < ActiveSupport::TestCase
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
    assert_equal 1, @chat.turn_count
    assert @chat.messages.where(role: "assistant").exists?
  end

  test "developer: writes a file using the Write tool" do
    workspace = Rails.root.join("tmp", "workspaces", "developer")
    FileUtils.mkdir_p(workspace)

    chat = Chat.create!(agent_name: "developer")
    chat.messages.create!(role: "user", content: 'Write "test content" to test.txt')

    VCR.use_cassette("llm_job/developer_write_file") do
      LlmJob.perform_now(chat)
    end

    chat.reload
    assert chat.completed?
    assert chat.messages.joins(:tool_calls).exists?
    assert File.exist?(workspace.join("test.txt"))
  ensure
    FileUtils.rm_rf(workspace.join("test.txt"))
  end
end
