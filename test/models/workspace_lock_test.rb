require "test_helper"

class WorkspaceLockTest < ActiveSupport::TestCase
  setup do
    @agent = Daan::Core::Agent.new(
      name: "developer", display_name: "Dev",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You are a developer.", max_steps: 10
    )
    Daan::Core::AgentRegistry.register(@agent)
    @chat_a = Chat.create!(agent_name: "developer")
    @chat_b = Chat.create!(agent_name: "developer")
  end

  test "acquire grants lock to first chat" do
    result = WorkspaceLock.acquire(chat: @chat_a, agent_name: "developer")
    assert result.acquired?
    assert_nil result.previous_holder_chat_id
  end

  test "acquire denies lock when held by another chat with active job" do
    WorkspaceLock.acquire(chat: @chat_a, agent_name: "developer")
    @chat_a.update_column(:task_status, "in_progress")
    gid = @chat_a.to_global_id.to_s
    SolidQueue::Job.create!(
      class_name: "LlmJob",
      queue_name: "default",
      arguments: { "job_class" => "LlmJob", "arguments" => [ { "_aj_globalid" => gid } ] }.to_json
    )
    result = WorkspaceLock.acquire(chat: @chat_b, agent_name: "developer")
    refute result.acquired?
  end

  test "acquire succeeds when same chat re-acquires" do
    WorkspaceLock.acquire(chat: @chat_a, agent_name: "developer")
    result = WorkspaceLock.acquire(chat: @chat_a, agent_name: "developer")
    assert result.acquired?
  end

  test "same chat re-acquire refreshes updated_at" do
    WorkspaceLock.acquire(chat: @chat_a, agent_name: "developer")
    lock = WorkspaceLock.find_by(agent_name: "developer")
    lock.update_column(:updated_at, 5.minutes.ago)

    WorkspaceLock.acquire(chat: @chat_a, agent_name: "developer")
    lock.reload
    assert lock.updated_at > 1.second.ago
  end

  test "release makes lock available to other chats" do
    WorkspaceLock.acquire(chat: @chat_a, agent_name: "developer")
    WorkspaceLock.release(chat: @chat_a, agent_name: "developer")
    result = WorkspaceLock.acquire(chat: @chat_b, agent_name: "developer")
    assert result.acquired?
  end

  test "acquire after release records previous holder" do
    WorkspaceLock.acquire(chat: @chat_a, agent_name: "developer")
    WorkspaceLock.release(chat: @chat_a, agent_name: "developer")
    result = WorkspaceLock.acquire(chat: @chat_b, agent_name: "developer")
    assert result.acquired?
    assert_equal @chat_a.id, result.previous_holder_chat_id
  end

  test "acquire re-acquires same chat without recording previous holder" do
    WorkspaceLock.acquire(chat: @chat_a, agent_name: "developer")
    result = WorkspaceLock.acquire(chat: @chat_a, agent_name: "developer")
    assert result.acquired?
    assert_nil result.previous_holder_chat_id
  end

  test "acquire steals lock when holder chat is not in_progress" do
    WorkspaceLock.acquire(chat: @chat_a, agent_name: "developer")
    @chat_a.update_column(:task_status, "completed")
    result = WorkspaceLock.acquire(chat: @chat_b, agent_name: "developer")
    assert result.acquired?
    assert_equal @chat_a.id, result.previous_holder_chat_id
  end

  test "acquire does not steal lock when recently acquired even without active job" do
    WorkspaceLock.acquire(chat: @chat_a, agent_name: "developer")
    @chat_a.update_column(:task_status, "in_progress")
    # Lock was just acquired (within grace period) — not stale even without a job
    result = WorkspaceLock.acquire(chat: @chat_b, agent_name: "developer")
    refute result.acquired?
  end

  test "acquire steals lock when holder chat is in_progress with no job and grace period expired" do
    WorkspaceLock.acquire(chat: @chat_a, agent_name: "developer")
    @chat_a.update_column(:task_status, "in_progress")
    # Age the lock past the grace period
    WorkspaceLock.find_by(agent_name: "developer").update_column(:updated_at, 31.seconds.ago)
    result = WorkspaceLock.acquire(chat: @chat_b, agent_name: "developer")
    assert result.acquired?
    assert_equal @chat_a.id, result.previous_holder_chat_id
  end

  test "acquire does not steal lock when holder chat is in_progress with unfinished LlmJob" do
    WorkspaceLock.acquire(chat: @chat_a, agent_name: "developer")
    @chat_a.update_column(:task_status, "in_progress")
    gid = @chat_a.to_global_id.to_s
    SolidQueue::Job.create!(
      class_name: "LlmJob",
      queue_name: "default",
      arguments: { "job_class" => "LlmJob", "arguments" => [ { "_aj_globalid" => gid } ] }.to_json
    )
    result = WorkspaceLock.acquire(chat: @chat_b, agent_name: "developer")
    refute result.acquired?
  end
end
