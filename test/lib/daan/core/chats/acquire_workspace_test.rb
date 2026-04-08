require "test_helper"

class Daan::Core::Chats::AcquireWorkspaceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionCable::TestHelper

  setup do
    @agent = Daan::Core::Agent.new(
      name: "developer", display_name: "Dev",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You are a developer.", max_steps: 10
    )
    Daan::Core::AgentRegistry.register(@agent)
    @chat = Chat.create!(agent_name: "developer")
  end

  test "returns acquire result when lock is acquired" do
    result = Daan::Core::Chats::AcquireWorkspace.call(@chat)
    assert result
    assert result.acquired?
    assert_nil result.previous_holder_chat_id
  end

  test "returns result with previous holder when workspace changed hands" do
    other_chat = Chat.create!(agent_name: "developer")
    WorkspaceLock.acquire(chat: other_chat, agent_name: "developer")
    WorkspaceLock.release(chat: other_chat, agent_name: "developer")

    result = Daan::Core::Chats::AcquireWorkspace.call(@chat)
    assert result.acquired?
    assert_equal other_chat.id, result.previous_holder_chat_id
  end

  test "returns false and re-enqueues when lock is held by another chat with active job" do
    other_chat = Chat.create!(agent_name: "developer")
    other_chat.update_column(:task_status, "in_progress")
    WorkspaceLock.acquire(chat: other_chat, agent_name: "developer")
    gid = other_chat.to_global_id.to_s
    SolidQueue::Job.create!(
      class_name: "LlmJob",
      queue_name: "default",
      arguments: { "job_class" => "LlmJob", "arguments" => [ { "_aj_globalid" => gid } ] }.to_json
    )
    assert_nil Daan::Core::Chats::AcquireWorkspace.call(@chat)
    assert_enqueued_with(job: LlmJob, args: [ @chat ])
  end

  test "broadcasts queued status when lock is held" do
    other_chat = Chat.create!(agent_name: "developer")
    other_chat.update_column(:task_status, "in_progress")
    WorkspaceLock.acquire(chat: other_chat, agent_name: "developer")
    gid = other_chat.to_global_id.to_s
    SolidQueue::Job.create!(
      class_name: "LlmJob",
      queue_name: "default",
      arguments: { "job_class" => "LlmJob", "arguments" => [ { "_aj_globalid" => gid } ] }.to_json
    )

    assert_broadcasts("chat_#{@chat.id}", 1) do
      Daan::Core::Chats::AcquireWorkspace.call(@chat)
    end
  end
end
