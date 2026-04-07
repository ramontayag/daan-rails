require "test_helper"

class Daan::Chats::AcquireWorkspaceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionCable::TestHelper

  setup do
    @agent = Daan::Agent.new(
      name: "developer", display_name: "Dev",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You are a developer.", max_steps: 10
    )
    Daan::AgentRegistry.register(@agent)
    @chat = Chat.create!(agent_name: "developer")
  end

  test "returns true when lock is acquired" do
    assert Daan::Chats::AcquireWorkspace.call(@chat)
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
    assert_not Daan::Chats::AcquireWorkspace.call(@chat)
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
      Daan::Chats::AcquireWorkspace.call(@chat)
    end
  end
end
