# Workspace Concurrency V1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure only one chat actively uses an agent's workspace at a time. Other chats queue up and wait.

**Architecture:** A `WorkspaceLock` model tracks which chat holds the lock for each agent. `ConversationRunner` acquires the lock before running a step; if locked by another chat, the job re-enqueues with a delay. Lock is released when the conversation reaches a terminal state (completed/blocked/failed). Stale locks (from crashed jobs) are detected by checking holder chat status and whether an unfinished LlmJob exists in Solid Queue.

**Tech Stack:** Rails 8.1, Minitest, AASM, Solid Queue

**Spec:** `docs/shaping-workspace-concurrency.md` (Shape A, parts A1–A4)

---

### Task 1: WorkspaceLock model and migration ✅

Completed. Created WorkspaceLock model with acquire/release, migration, and 6 tests.

Note: The committed migration includes a `job_id` column that is no longer needed. Task 2 will remove it and replace the stale detection approach.

---

### Task 2: Stale lock detection + remove job_id

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_remove_job_id_from_workspace_locks.rb`
- Modify: `app/models/workspace_lock.rb` — remove job_id references, add `stale?` method
- Modify: `test/models/workspace_lock_test.rb` — add stale detection tests

- [ ] **Step 1: Write the failing tests for stale lock detection**

Append to `test/models/workspace_lock_test.rb`:

```ruby
test "acquire steals lock when holder chat is not in_progress" do
  WorkspaceLock.acquire(chat: @chat_a, agent_name: "developer")
  @chat_a.update_column(:task_status, "completed")
  result = WorkspaceLock.acquire(chat: @chat_b, agent_name: "developer")
  assert result.acquired?
  assert_equal @chat_a.id, result.previous_holder_chat_id
end

test "acquire steals lock when holder chat is in_progress but has no unfinished LlmJob" do
  WorkspaceLock.acquire(chat: @chat_a, agent_name: "developer")
  @chat_a.update_column(:task_status, "in_progress")
  result = WorkspaceLock.acquire(chat: @chat_b, agent_name: "developer")
  assert result.acquired?
  assert_equal @chat_a.id, result.previous_holder_chat_id
end

test "acquire does not steal lock when holder chat is in_progress with unfinished LlmJob" do
  WorkspaceLock.acquire(chat: @chat_a, agent_name: "developer")
  @chat_a.update_column(:task_status, "in_progress")
  # Create an unfinished LlmJob for chat_a in Solid Queue
  gid = @chat_a.to_global_id.to_s
  SolidQueue::Job.create!(
    class_name: "LlmJob",
    queue_name: "default",
    arguments: { "job_class" => "LlmJob", "arguments" => [{ "_aj_globalid" => gid }] }.to_json
  )
  result = WorkspaceLock.acquire(chat: @chat_b, agent_name: "developer")
  refute result.acquired?
end
```

- [ ] **Step 2: Run tests to verify new tests fail**

Run: `bin/rails test test/models/workspace_lock_test.rb`
Expected: New stale detection tests FAIL

- [ ] **Step 3: Create migration to remove job_id**

```bash
bin/rails generate migration RemoveJobIdFromWorkspaceLocks
```

Edit the migration:

```ruby
class RemoveJobIdFromWorkspaceLocks < ActiveRecord::Migration[8.1]
  def change
    remove_column :workspace_locks, :job_id, :bigint
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 4: Update WorkspaceLock model**

Replace `app/models/workspace_lock.rb`:

```ruby
class WorkspaceLock < ApplicationRecord
  belongs_to :holder_chat, class_name: "Chat", optional: true
  belongs_to :previous_holder_chat, class_name: "Chat", optional: true

  AcquireResult = Struct.new(:acquired?, :previous_holder_chat_id, keyword_init: true)

  def self.acquire(chat:, agent_name:)
    lock = find_or_create_by!(agent_name: agent_name)

    lock.with_lock do
      if lock.holder_chat_id.nil?
        previous = lock.previous_holder_chat_id
        lock.update!(holder_chat: chat)
        changed_hands = previous && previous != chat.id
        AcquireResult.new(acquired?: true, previous_holder_chat_id: changed_hands ? previous : nil)
      elsif lock.holder_chat_id == chat.id
        AcquireResult.new(acquired?: true, previous_holder_chat_id: nil)
      elsif lock.stale?
        stale_holder_id = lock.holder_chat_id
        lock.update!(holder_chat: chat, previous_holder_chat_id: stale_holder_id)
        AcquireResult.new(acquired?: true, previous_holder_chat_id: stale_holder_id)
      else
        AcquireResult.new(acquired?: false, previous_holder_chat_id: nil)
      end
    end
  end

  def self.release(chat:, agent_name:)
    lock = find_by(agent_name: agent_name)
    return unless lock

    lock.with_lock do
      return unless lock.holder_chat_id == chat.id

      lock.update!(holder_chat: nil, previous_holder_chat: chat)
    end
  end

  def stale?
    return true unless holder_chat&.in_progress?

    gid = holder_chat.to_global_id.to_s
    !SolidQueue::Job
      .where(class_name: "LlmJob", finished_at: nil)
      .where("arguments LIKE ?", "%#{gid}%")
      .exists?
  end
end
```

- [ ] **Step 5: Update existing tests to remove job_id references**

In `test/models/workspace_lock_test.rb`, update any `WorkspaceLock.acquire` calls that pass `job_id:` to remove that argument. The existing 6 tests should still pass as-is since `job_id` was optional, but verify.

- [ ] **Step 6: Run all tests to verify they pass**

Run: `bin/rails test test/models/workspace_lock_test.rb`
Expected: All 9 tests PASS

- [ ] **Step 7: Commit**

```bash
git add app/models/workspace_lock.rb db/migrate/*_remove_job_id_from_workspace_locks.rb test/models/workspace_lock_test.rb db/schema.rb
git commit -m "feat: stale lock detection via chat status + Solid Queue job existence

Replace job_id-based stale detection with a two-part check:
1. Holder chat is not in_progress → stale
2. Holder chat is in_progress but no unfinished LlmJob exists → stale
Uses GlobalID to match chat in serialized job arguments."
```

---

### Task 3: AcquireWorkspace service

**Files:**
- Create: `lib/daan/chats/acquire_workspace.rb`
- Create: `test/lib/daan/chats/acquire_workspace_test.rb`

- [ ] **Step 1: Write the failing test for AcquireWorkspace**

Create `test/lib/daan/chats/acquire_workspace_test.rb`:

```ruby
require "test_helper"

class Daan::Chats::AcquireWorkspaceTest < ActiveSupport::TestCase
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

    # Create an unfinished LlmJob so lock isn't stale
    gid = other_chat.to_global_id.to_s
    SolidQueue::Job.create!(
      class_name: "LlmJob",
      queue_name: "default",
      arguments: { "job_class" => "LlmJob", "arguments" => [{ "_aj_globalid" => gid }] }.to_json
    )

    assert_not Daan::Chats::AcquireWorkspace.call(@chat)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/lib/daan/chats/acquire_workspace_test.rb`
Expected: FAIL — `Daan::Chats::AcquireWorkspace` not defined

- [ ] **Step 3: Create AcquireWorkspace service**

Create `lib/daan/chats/acquire_workspace.rb`:

```ruby
module Daan
  module Chats
    class AcquireWorkspace
      RETRY_DELAY = 5.seconds

      def self.call(chat)
        result = WorkspaceLock.acquire(chat: chat, agent_name: chat.agent_name)

        if result.acquired?
          Rails.logger.info("[AcquireWorkspace] chat_id=#{chat.id} acquired lock for agent=#{chat.agent_name}")
          true
        else
          Rails.logger.info("[AcquireWorkspace] chat_id=#{chat.id} lock held for agent=#{chat.agent_name}, re-enqueuing in #{RETRY_DELAY}")
          LlmJob.set(wait: RETRY_DELAY).perform_later(chat)
          false
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/lib/daan/chats/acquire_workspace_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/daan/chats/acquire_workspace.rb test/lib/daan/chats/acquire_workspace_test.rb
git commit -m "feat: add AcquireWorkspace service for lock acquisition with back-off"
```

---

### Task 4: ReleaseWorkspace service

**Files:**
- Create: `lib/daan/chats/release_workspace.rb`
- Create: `test/lib/daan/chats/release_workspace_test.rb`

- [ ] **Step 1: Write the failing test for ReleaseWorkspace**

Create `test/lib/daan/chats/release_workspace_test.rb`:

```ruby
require "test_helper"

class Daan::Chats::ReleaseWorkspaceTest < ActiveSupport::TestCase
  setup do
    @agent = Daan::Agent.new(
      name: "developer", display_name: "Dev",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You are a developer.", max_steps: 10
    )
    Daan::AgentRegistry.register(@agent)
    @chat = Chat.create!(agent_name: "developer")
    WorkspaceLock.acquire(chat: @chat, agent_name: "developer")
  end

  test "releases the lock" do
    Daan::Chats::ReleaseWorkspace.call(@chat)
    other_chat = Chat.create!(agent_name: "developer")
    result = WorkspaceLock.acquire(chat: other_chat, agent_name: "developer")
    assert result.acquired?
  end

  test "is safe to call when no lock exists" do
    Daan::Chats::ReleaseWorkspace.call(Chat.create!(agent_name: "developer"))
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/lib/daan/chats/release_workspace_test.rb`
Expected: FAIL — `Daan::Chats::ReleaseWorkspace` not defined

- [ ] **Step 3: Create ReleaseWorkspace service**

Create `lib/daan/chats/release_workspace.rb`:

```ruby
module Daan
  module Chats
    class ReleaseWorkspace
      def self.call(chat)
        WorkspaceLock.release(chat: chat, agent_name: chat.agent_name)
        Rails.logger.info("[ReleaseWorkspace] chat_id=#{chat.id} released lock for agent=#{chat.agent_name}")
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/lib/daan/chats/release_workspace_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/daan/chats/release_workspace.rb test/lib/daan/chats/release_workspace_test.rb
git commit -m "feat: add ReleaseWorkspace service"
```

---

### Task 5: Integrate lock into ConversationRunner and FinishOrReenqueue

**Files:**
- Modify: `lib/daan/conversation_runner.rb`
- Modify: `lib/daan/chats/finish_or_reenqueue.rb`
- Modify: `app/jobs/llm_job.rb`
- Create: `test/lib/daan/conversation_runner_workspace_lock_test.rb`

- [ ] **Step 1: Write the failing integration test**

Create `test/lib/daan/conversation_runner_workspace_lock_test.rb`:

```ruby
require "test_helper"

class Daan::ConversationRunnerWorkspaceLockTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @agent = Daan::Agent.new(
      name: "developer", display_name: "Dev",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You are a developer.", max_steps: 10,
      workspace: Daan::Workspace.new(Dir.mktmpdir)
    )
    Daan::AgentRegistry.register(@agent)
  end

  test "acquires lock before running and releases on completion" do
    chat = Chat.create!(agent_name: "developer")
    chat.messages.create!(role: "user", content: "hello", visible: true)

    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(status: 200, body: fake_anthropic_response(text: "hi"), headers: { "Content-Type" => "application/json" })

    Daan::ConversationRunner.call(chat)

    lock = WorkspaceLock.find_by(agent_name: "developer")
    assert_nil lock.holder_chat_id, "Lock should be released after conversation completes"
    assert_equal chat.id, lock.previous_holder_chat_id
  end

  test "does not run when lock is held by another in-progress chat with active job" do
    chat_a = Chat.create!(agent_name: "developer")
    chat_b = Chat.create!(agent_name: "developer")
    chat_b.messages.create!(role: "user", content: "hello", visible: true)

    # chat_a holds the lock and is in_progress with an active job
    chat_a.update_column(:task_status, "in_progress")
    WorkspaceLock.acquire(chat: chat_a, agent_name: "developer")
    gid = chat_a.to_global_id.to_s
    SolidQueue::Job.create!(
      class_name: "LlmJob",
      queue_name: "default",
      arguments: { "job_class" => "LlmJob", "arguments" => [{ "_aj_globalid" => gid }] }.to_json
    )

    Daan::ConversationRunner.call(chat_b)

    lock = WorkspaceLock.find_by(agent_name: "developer")
    assert_equal chat_a.id, lock.holder_chat_id, "Lock should still be held by chat_a"
    assert_enqueued_with(job: LlmJob, args: [chat_b])
  end

  test "releases lock when conversation fails" do
    chat = Chat.create!(agent_name: "developer")
    chat.messages.create!(role: "user", content: "hello", visible: true)

    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(status: 500, body: '{"error": "internal"}', headers: { "Content-Type" => "application/json" })

    assert_raises(RubyLLM::Error) do
      Daan::ConversationRunner.call(chat)
    end

    lock = WorkspaceLock.find_by(agent_name: "developer")
    assert_nil lock.holder_chat_id, "Lock should be released after failure"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/lib/daan/conversation_runner_workspace_lock_test.rb`
Expected: FAIL — lock not acquired/released (ConversationRunner doesn't use it yet)

- [ ] **Step 3: Add lock acquisition to ConversationRunner**

In `lib/daan/conversation_runner.rb`, modify the `call` method. Add `return unless Chats::AcquireWorkspace.call(chat)` early, and `Chats::ReleaseWorkspace.call(chat)` in the already_responded? path:

```ruby
def self.call(chat)
  agent = chat.agent

  chat.reload
  if already_responded?(chat)
    Rails.logger.info("[ConversationRunner] chat_id=#{chat.id} skipping — last user message already has a response")
    if chat.in_progress?
      chat.finish!
      chat.broadcast_agent_status
      chat.broadcast_chat_cost
      Chats::NotifyParent.on_completion(chat)
    end
    Chats::ReleaseWorkspace.call(chat)
    return
  end

  return unless Chats::AcquireWorkspace.call(chat)

  context_user_message_id = chat.messages.where(role: "user").maximum(:id)

  # ... rest unchanged
end
```

- [ ] **Step 4: Add lock release to FinishOrReenqueue terminal paths**

In `lib/daan/chats/finish_or_reenqueue.rb`, add `ReleaseWorkspace.call(chat)` to `finish_conversation` (after `chat.finish!`) and `block_conversation` (after `chat.block!`).

Note: `continue_conversation` does NOT release — the lock persists across steps.

- [ ] **Step 5: Add lock release to LlmJob failure path**

In `app/jobs/llm_job.rb`, add `Daan::Chats::ReleaseWorkspace.call(chat)` in the rescue block after `chat.fail!`.

- [ ] **Step 6: Run tests to verify they pass**

Run: `bin/rails test test/lib/daan/conversation_runner_workspace_lock_test.rb`
Expected: All 3 tests PASS

- [ ] **Step 7: Run the full test suite**

Run: `bin/rails test && bin/rails test:system`
Expected: All tests PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/daan/conversation_runner.rb lib/daan/chats/finish_or_reenqueue.rb app/jobs/llm_job.rb test/lib/daan/conversation_runner_workspace_lock_test.rb
git commit -m "feat: integrate workspace lock into ConversationRunner and FinishOrReenqueue"
```

---

### Task 6: End-to-end integration test

**Files:**
- Create: `test/integration/workspace_lock_integration_test.rb`

- [ ] **Step 1: Write the integration test**

Create `test/integration/workspace_lock_integration_test.rb`:

```ruby
require "test_helper"

class WorkspaceLockIntegrationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @agent = Daan::Agent.new(
      name: "developer", display_name: "Dev",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You are a developer.", max_steps: 10,
      workspace: Daan::Workspace.new(Dir.mktmpdir)
    )
    Daan::AgentRegistry.register(@agent)
  end

  test "second chat waits when first chat holds workspace lock" do
    chat_a = Chat.create!(agent_name: "developer")
    chat_b = Chat.create!(agent_name: "developer")
    chat_a.messages.create!(role: "user", content: "task A", visible: true)
    chat_b.messages.create!(role: "user", content: "task B", visible: true)

    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(status: 200, body: fake_anthropic_response(text: "done"), headers: { "Content-Type" => "application/json" })

    # Run chat_a — it should acquire lock, complete, release
    perform_enqueued_jobs { LlmJob.perform_later(chat_a) }

    chat_a.reload
    assert chat_a.completed?

    # Lock should now be released
    lock = WorkspaceLock.find_by(agent_name: "developer")
    assert_nil lock.holder_chat_id

    # Run chat_b — should acquire lock successfully
    perform_enqueued_jobs { LlmJob.perform_later(chat_b) }

    chat_b.reload
    assert chat_b.completed?
  end
end
```

- [ ] **Step 2: Run test to verify it passes**

Run: `bin/rails test test/integration/workspace_lock_integration_test.rb`
Expected: PASS

- [ ] **Step 3: Run the full test suite**

Run: `bin/rails test && bin/rails test:system`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add test/integration/workspace_lock_integration_test.rb
git commit -m "test: add end-to-end integration test for workspace lock"
```
