require "test_helper"

class Daan::Core::ConversationRunnerWorkspaceLockTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @agent = Daan::Core::Agent.new(
      name: "developer", display_name: "Dev",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You are a developer.", max_steps: 10,
      workspace: Daan::Core::Workspace.new(Dir.mktmpdir)
    )
    Daan::Core::AgentRegistry.register(@agent)
  end

  test "acquires lock before running and releases on completion" do
    chat = Chat.create!(agent_name: "developer")
    chat.messages.create!(role: "user", content: "Say exactly: ok", visible: true)

    VCR.use_cassette("workspace_lock/acquire_and_release") do
      Daan::Core::ConversationRunner.call(chat)
    end

    lock = WorkspaceLock.find_by(agent_name: "developer")
    assert_nil lock.holder_chat_id, "Lock should be released after conversation completes"
    assert_equal chat.id, lock.previous_holder_chat_id
  end

  test "does not run when lock is held by another in-progress chat with active job" do
    chat_a = Chat.create!(agent_name: "developer")
    chat_b = Chat.create!(agent_name: "developer")
    chat_b.messages.create!(role: "user", content: "hello", visible: true)

    chat_a.update_column(:task_status, "in_progress")
    WorkspaceLock.acquire(chat: chat_a, agent_name: "developer")
    gid = chat_a.to_global_id.to_s
    SolidQueue::Job.create!(
      class_name: "LlmJob",
      queue_name: "default",
      arguments: { "job_class" => "LlmJob", "arguments" => [ { "_aj_globalid" => gid } ] }.to_json
    )

    Daan::Core::ConversationRunner.call(chat_b)

    lock = WorkspaceLock.find_by(agent_name: "developer")
    assert_equal chat_a.id, lock.holder_chat_id, "Lock should still be held by chat_a"
    assert_enqueued_with(job: LlmJob, args: [ chat_b ])
  end

  test "releases lock when conversation fails" do
    chat = Chat.create!(agent_name: "developer")
    chat.messages.create!(role: "user", content: "hello", visible: true)

    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(status: 500, body: '{"error": "internal"}', headers: { "Content-Type" => "application/json" })

    assert_raises(RubyLLM::Error) do
      LlmJob.perform_now(chat)
    end

    lock = WorkspaceLock.find_by(agent_name: "developer")
    assert_nil lock.holder_chat_id, "Lock should be released after failure"
  end
end
