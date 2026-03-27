# Scheduled Tasks Slice 3: One-Shot Tasks + Agent Self-Scheduling — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend scheduled tasks with one-shot support and expose a `schedule_task` tool so agents can schedule future work during a conversation.

**Prerequisite:** Slice 2 (recurring tasks) must be implemented first. The `ScheduledTask` model, `ScheduledTaskPollerJob`, `ScheduledTaskRunnerJob`, the tasks index UI, and the `recurring.yml` entry must all exist before starting this slice.

**Architecture:** `ScheduledTask` gains three new columns (`task_type` enum, `run_at` datetime, `source_chat_id` FK) and a new `one_shot` enum value alongside the existing `recurring` default. `ScheduledTaskPollerJob` gets a second branch to fire one-shot tasks whose `run_at <= Time.current` and `enabled: true`. `ScheduledTaskRunnerJob` sets `enabled: false` on one-shot tasks after firing. A new `Daan::Core::ScheduleTask` tool (`lib/daan/core/schedule_task.rb`) follows the existing tool pattern — `class ScheduleTask < RubyLLM::Tool` with `include Daan::Core::Tool.module(timeout: 10.seconds)` — accepts `agent_name`, `message`, and `run_at` (ISO8601 string), creates the record, and returns a confirmation string; agents add it to their `tools:` list in their `.md` file. The tasks index view gains a second section below recurring tasks for one-shot tasks with a link to `source_chat`.

**Tech Stack:** Rails 8.1, Minitest, ActiveRecord enum, RubyLLM tool DSL.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `db/migrate/<timestamp>_add_one_shot_fields_to_scheduled_tasks.rb` | Adds `task_type` (integer, not null, default 0), `run_at` (datetime, nullable), `source_chat_id` (bigint, nullable, FK to chats) |
| Modify | `app/models/scheduled_task.rb` | Add `enum :task_type`, `belongs_to :source_chat`, `scope :one_shot_due`, validations |
| Modify | `test/models/scheduled_task_test.rb` | Tests for new enum, scopes, and validations |
| Modify | `app/jobs/scheduled_task_poller_job.rb` | Add one-shot branch |
| Modify | `test/jobs/scheduled_task_poller_job_test.rb` | Tests for one-shot firing logic |
| Modify | `app/jobs/scheduled_task_runner_job.rb` | Disable one-shot tasks after firing |
| Modify | `test/jobs/scheduled_task_runner_job_test.rb` | Test `enabled: false` after one-shot runs |
| Create | `lib/daan/core/schedule_task.rb` | `Daan::Core::ScheduleTask` tool |
| Create | `test/lib/daan/core/schedule_task_test.rb` | Unit tests for the tool |
| Modify | `app/views/scheduled_tasks/index.html.erb` | Add one-shot section below recurring |
| Modify | `lib/daan/core/agents/chief_of_staff.md` | Add `Daan::Core::ScheduleTask` to tools list |

---

## Task 0: Migration — add one-shot columns to `scheduled_tasks`

**Files:**
- Create: `db/migrate/<timestamp>_add_one_shot_fields_to_scheduled_tasks.rb`

- [ ] **Step 1: Generate and write the migration**

Run:

```bash
bin/rails generate migration AddOneShotFieldsToScheduledTasks task_type:integer run_at:datetime source_chat_id:bigint
```

Then open the generated file and replace its content with:

```ruby
class AddOneShotFieldsToScheduledTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :scheduled_tasks, :task_type, :integer, null: false, default: 0
    add_column :scheduled_tasks, :run_at, :datetime, null: true
    add_column :scheduled_tasks, :source_chat_id, :bigint, null: true

    add_foreign_key :scheduled_tasks, :chats, column: :source_chat_id
    add_index :scheduled_tasks, :source_chat_id
    add_index :scheduled_tasks, [ :task_type, :enabled, :run_at ],
              name: "index_scheduled_tasks_on_type_enabled_run_at"
  end
end
```

- [ ] **Step 2: Run the migration**

```bash
bin/rails db:migrate
```

Expected output ends with: `== AddOneShotFieldsToScheduledTasks: migrated`

- [ ] **Step 3: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "$(cat <<'EOF'
feat: add task_type, run_at, source_chat_id to scheduled_tasks

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 1: `ScheduledTask` model — enum, association, scopes, validations

**Files:**
- Modify: `app/models/scheduled_task.rb`
- Modify: `test/models/scheduled_task_test.rb`

- [ ] **Step 1: Write the failing tests**

Add to `test/models/scheduled_task_test.rb`:

```ruby
# --- task_type enum ---

test "task_type defaults to recurring" do
  task = ScheduledTask.new(agent_name: "chief_of_staff", message: "hi", schedule: "every day", timezone: "UTC")
  assert task.recurring?
end

test "task_type can be set to one_shot" do
  task = ScheduledTask.new(agent_name: "chief_of_staff", message: "hi", task_type: :one_shot)
  assert task.one_shot?
end

# --- source_chat association ---

test "belongs_to source_chat (optional)" do
  chat = Chat.create!(agent_name: "chief_of_staff")
  task = ScheduledTask.create!(agent_name: "chief_of_staff", message: "m", task_type: :one_shot,
                               run_at: 5.minutes.from_now, source_chat: chat)
  assert_equal chat, task.reload.source_chat
end

test "source_chat is optional" do
  task = ScheduledTask.new(agent_name: "chief_of_staff", message: "hi", task_type: :one_shot,
                           run_at: 5.minutes.from_now)
  task.valid?
  assert_nil task.errors[:source_chat].presence
end

# --- one_shot_due scope ---

test "one_shot_due returns enabled one_shot tasks whose run_at is in the past" do
  Daan::AgentRegistry.register(
    Daan::Agent.new(name: "chief_of_staff", display_name: "CoS", model_name: "m",
                    system_prompt: "p", max_steps: 5)
  )
  due = ScheduledTask.create!(agent_name: "chief_of_staff", message: "due",
                              task_type: :one_shot, run_at: 1.minute.ago, enabled: true)
  _future = ScheduledTask.create!(agent_name: "chief_of_staff", message: "future",
                                  task_type: :one_shot, run_at: 5.minutes.from_now, enabled: true)
  _disabled = ScheduledTask.create!(agent_name: "chief_of_staff", message: "disabled",
                                    task_type: :one_shot, run_at: 1.minute.ago, enabled: false)
  _recurring = ScheduledTask.create!(agent_name: "chief_of_staff", message: "recurring",
                                     schedule: "every day", timezone: "UTC", enabled: true)

  result = ScheduledTask.one_shot_due
  assert_includes result, due
  assert_not_includes result, _future
  assert_not_includes result, _disabled
  assert_not_includes result, _recurring
end

# --- run_at validation ---

test "one_shot task is invalid without run_at" do
  task = ScheduledTask.new(agent_name: "chief_of_staff", message: "m", task_type: :one_shot)
  assert task.invalid?
  assert_includes task.errors[:run_at], "can't be blank"
end

test "recurring task does not require run_at" do
  task = ScheduledTask.new(agent_name: "chief_of_staff", message: "m",
                           schedule: "every day", timezone: "UTC", task_type: :recurring)
  task.valid?
  assert_empty task.errors[:run_at]
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/models/scheduled_task_test.rb -n "/task_type|source_chat|one_shot_due|run_at/"
```

Expected: failures — enum, scope, and association not defined yet.

- [ ] **Step 3: Update `ScheduledTask` model**

In `app/models/scheduled_task.rb`, add the following (keeping all existing code):

```ruby
enum :task_type, { recurring: 0, one_shot: 1 }, default: :recurring

belongs_to :source_chat, class_name: "Chat", optional: true

scope :one_shot_due, -> {
  where(
    task_type: task_types[:one_shot],
    enabled: true
  ).where(ScheduledTask.arel_table[:run_at].lteq(Time.current))
}

validates :run_at, presence: true, if: :one_shot?
```

- [ ] **Step 4: Run the model tests to confirm they pass**

```bash
bin/rails test test/models/scheduled_task_test.rb
```

Expected: all pass, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/models/scheduled_task.rb test/models/scheduled_task_test.rb
git commit -m "feat: add task_type enum, one_shot_due scope, and source_chat association to ScheduledTask"
```

---

## Task 2: `ScheduledTaskPollerJob` — one-shot branch

The poller runs every minute. It already fires recurring tasks. Add a second branch that collects `ScheduledTask.one_shot_due` and enqueues `ScheduledTaskRunnerJob` for each one.

**Files:**
- Modify: `app/jobs/scheduled_task_poller_job.rb`
- Modify: `test/jobs/scheduled_task_poller_job_test.rb`

- [ ] **Step 1: Write the failing tests**

Add to `test/jobs/scheduled_task_poller_job_test.rb`:

```ruby
# --- one-shot tests ---

test "enqueues ScheduledTaskRunnerJob for a due one-shot task" do
  Daan::AgentRegistry.register(
    Daan::Agent.new(name: "chief_of_staff", display_name: "CoS", model_name: "m",
                    system_prompt: "p", max_steps: 5)
  )
  task = ScheduledTask.create!(agent_name: "chief_of_staff", message: "ping",
                               task_type: :one_shot, run_at: 1.minute.ago, enabled: true)

  assert_enqueued_with(job: ScheduledTaskRunnerJob, args: [task]) do
    ScheduledTaskPollerJob.new.perform
  end
end

test "does not enqueue for a future one-shot task" do
  Daan::AgentRegistry.register(
    Daan::Agent.new(name: "chief_of_staff", display_name: "CoS", model_name: "m",
                    system_prompt: "p", max_steps: 5)
  )
  ScheduledTask.create!(agent_name: "chief_of_staff", message: "future",
                        task_type: :one_shot, run_at: 10.minutes.from_now, enabled: true)

  assert_no_enqueued_jobs(only: ScheduledTaskRunnerJob) do
    ScheduledTaskPollerJob.new.perform
  end
end

test "does not enqueue for a disabled one-shot task" do
  Daan::AgentRegistry.register(
    Daan::Agent.new(name: "chief_of_staff", display_name: "CoS", model_name: "m",
                    system_prompt: "p", max_steps: 5)
  )
  ScheduledTask.create!(agent_name: "chief_of_staff", message: "fired",
                        task_type: :one_shot, run_at: 1.minute.ago, enabled: false)

  assert_no_enqueued_jobs(only: ScheduledTaskRunnerJob) do
    ScheduledTaskPollerJob.new.perform
  end
end

test "enqueues for multiple due one-shot tasks in a single poll" do
  Daan::AgentRegistry.register(
    Daan::Agent.new(name: "chief_of_staff", display_name: "CoS", model_name: "m",
                    system_prompt: "p", max_steps: 5)
  )
  t1 = ScheduledTask.create!(agent_name: "chief_of_staff", message: "first",
                              task_type: :one_shot, run_at: 2.minutes.ago, enabled: true)
  t2 = ScheduledTask.create!(agent_name: "chief_of_staff", message: "second",
                              task_type: :one_shot, run_at: 1.minute.ago, enabled: true)

  assert_enqueued_jobs(2, only: ScheduledTaskRunnerJob) do
    ScheduledTaskPollerJob.new.perform
  end
end
```

- [ ] **Step 2: Run the new tests to confirm they fail**

```bash
bin/rails test test/jobs/scheduled_task_poller_job_test.rb -n "/one-shot/"
```

Expected: failures — one-shot branch not implemented.

- [ ] **Step 3: Add the one-shot branch to `ScheduledTaskPollerJob`**

In `app/jobs/scheduled_task_poller_job.rb`, add inside `perform` after the existing recurring block:

```ruby
# One-shot tasks: fire if run_at has passed and still enabled
ScheduledTask.one_shot_due.each do |task|
  ScheduledTaskRunnerJob.perform_later(task)
end
```

- [ ] **Step 4: Run the new tests to confirm they pass**

```bash
bin/rails test test/jobs/scheduled_task_poller_job_test.rb
```

Expected: all pass, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/jobs/scheduled_task_poller_job.rb test/jobs/scheduled_task_poller_job_test.rb
git commit -m "feat: add one-shot firing branch to ScheduledTaskPollerJob"
```

---

## Task 3: `ScheduledTaskRunnerJob` — disable one-shot after firing

After the runner enqueues `LlmJob` for a one-shot task, it must set `enabled: false` so the poller never fires it again.

**Files:**
- Modify: `app/jobs/scheduled_task_runner_job.rb`
- Modify: `test/jobs/scheduled_task_runner_job_test.rb`

- [ ] **Step 1: Write the failing tests**

Add to `test/jobs/scheduled_task_runner_job_test.rb`:

```ruby
test "sets enabled to false on a one-shot task after firing" do
  Daan::AgentRegistry.register(
    Daan::Agent.new(name: "chief_of_staff", display_name: "CoS", model_name: "m",
                    system_prompt: "p", max_steps: 5)
  )
  task = ScheduledTask.create!(agent_name: "chief_of_staff", message: "ping",
                               task_type: :one_shot, run_at: 1.minute.ago, enabled: true)

  ScheduledTaskRunnerJob.new.perform(task)

  assert_not task.reload.enabled, "expected one-shot task to be disabled after firing"
end

test "does not disable a recurring task after firing" do
  Daan::AgentRegistry.register(
    Daan::Agent.new(name: "chief_of_staff", display_name: "CoS", model_name: "m",
                    system_prompt: "p", max_steps: 5)
  )
  task = ScheduledTask.create!(agent_name: "chief_of_staff", message: "daily briefing",
                               task_type: :recurring, schedule: "every day", timezone: "UTC",
                               enabled: true)

  ScheduledTaskRunnerJob.new.perform(task)

  assert task.reload.enabled, "recurring task must remain enabled after firing"
end
```

- [ ] **Step 2: Run the new tests to confirm they fail**

```bash
bin/rails test test/jobs/scheduled_task_runner_job_test.rb -n "/disable/"
```

Expected: failure on the one-shot test — `enabled` is still `true`.

- [ ] **Step 3: Update `ScheduledTaskRunnerJob` to disable one-shot tasks**

In `app/jobs/scheduled_task_runner_job.rb`, after the `LlmJob.perform_later(chat)` call, add:

```ruby
task.update!(enabled: false) if task.one_shot?
```

The full `perform` method should look like:

```ruby
def perform(task)
  agent_name = task.agent_name
  chat = Chat.create!(agent_name: agent_name)
  chat.messages.create!(
    role: "system",
    content: "This conversation was started automatically by a scheduled task.",
    visible: false
  )
  chat.messages.create!(role: "user", content: task.message, visible: true)
  LlmJob.perform_later(chat)
  task.update!(enabled: false) if task.one_shot?
end
```

- [ ] **Step 4: Run the runner tests to confirm they pass**

```bash
bin/rails test test/jobs/scheduled_task_runner_job_test.rb
```

Expected: all pass, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/jobs/scheduled_task_runner_job.rb test/jobs/scheduled_task_runner_job_test.rb
git commit -m "feat: disable one-shot ScheduledTask after firing in ScheduledTaskRunnerJob"
```

---

## Task 4: `Daan::Core::ScheduleTask` tool

The tool lets an agent create a one-shot `ScheduledTask` from within a conversation. It follows the exact same pattern as `Daan::Core::DelegateTask` and `Daan::Core::ReportBack`: extends `RubyLLM::Tool`, `include Daan::Core::Tool.module(timeout: 10.seconds)`, declares params, takes `chat:` in `initialize`, and returns a plain string from `execute`.

**Files:**
- Create: `lib/daan/core/schedule_task.rb`
- Create: `test/lib/daan/core/schedule_task_test.rb`

- [ ] **Step 1: Write the failing tests**

Create `test/lib/daan/core/schedule_task_test.rb`:

```ruby
# test/lib/daan/core/schedule_task_test.rb
require "test_helper"

class Daan::Core::ScheduleTaskTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    RubyLLM::Models.instance.load_from_json!
    Daan::AgentRegistry.register(
      Daan::Agent.new(name: "chief_of_staff", display_name: "Chief of Staff",
                      model_name: "claude-haiku-4-5-20251001", system_prompt: "p", max_steps: 10)
    )
    @chat = Chat.create!(agent_name: "chief_of_staff")
    @tool = Daan::Core::ScheduleTask.new(chat: @chat)
  end

  test "creates a one_shot ScheduledTask" do
    run_at = 5.minutes.from_now.iso8601
    assert_difference "ScheduledTask.count", 1 do
      @tool.execute(agent_name: "chief_of_staff", message: "Run the daily report", run_at: run_at)
    end
    task = ScheduledTask.last
    assert task.one_shot?
  end

  test "sets the correct agent_name on the created task" do
    run_at = 5.minutes.from_now.iso8601
    @tool.execute(agent_name: "chief_of_staff", message: "Run the daily report", run_at: run_at)
    assert_equal "chief_of_staff", ScheduledTask.last.agent_name
  end

  test "sets the correct message on the created task" do
    run_at = 5.minutes.from_now.iso8601
    @tool.execute(agent_name: "chief_of_staff", message: "Run the daily report", run_at: run_at)
    assert_equal "Run the daily report", ScheduledTask.last.message
  end

  test "sets run_at from ISO8601 string on the created task" do
    future = 5.minutes.from_now
    @tool.execute(agent_name: "chief_of_staff", message: "ping", run_at: future.iso8601)
    assert_in_delta future.to_i, ScheduledTask.last.run_at.to_i, 1
  end

  test "sets source_chat_id to the current chat's id" do
    run_at = 5.minutes.from_now.iso8601
    @tool.execute(agent_name: "chief_of_staff", message: "ping", run_at: run_at)
    assert_equal @chat.id, ScheduledTask.last.source_chat_id
  end

  test "creates the task with enabled: true" do
    run_at = 5.minutes.from_now.iso8601
    @tool.execute(agent_name: "chief_of_staff", message: "ping", run_at: run_at)
    assert ScheduledTask.last.enabled
  end

  test "returns a confirmation string containing the agent name and run_at" do
    future = 5.minutes.from_now
    result = @tool.execute(agent_name: "chief_of_staff", message: "ping", run_at: future.iso8601)
    assert_includes result, "chief_of_staff"
    assert_kind_of String, result
  end

  test "returns an error string when agent_name is not in the registry" do
    run_at = 5.minutes.from_now.iso8601
    result = @tool.execute(agent_name: "ghost_agent", message: "ping", run_at: run_at)
    assert_match(/[Ee]rror/, result)
    assert_not_includes result, "Scheduled"
  end

  test "returns an error string when run_at is not a valid ISO8601 string" do
    result = @tool.execute(agent_name: "chief_of_staff", message: "ping", run_at: "not-a-date")
    assert_match(/[Ee]rror/, result)
  end

  test "does not create a task when agent_name is unknown" do
    run_at = 5.minutes.from_now.iso8601
    assert_no_difference "ScheduledTask.count" do
      @tool.execute(agent_name: "ghost_agent", message: "ping", run_at: run_at)
    end
  end

  test "does not create a task when run_at is invalid" do
    assert_no_difference "ScheduledTask.count" do
      @tool.execute(agent_name: "chief_of_staff", message: "ping", run_at: "bad")
    end
  end
end
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
bin/rails test test/lib/daan/core/schedule_task_test.rb
```

Expected: `NameError: uninitialized constant Daan::Core::ScheduleTask`

- [ ] **Step 3: Implement `Daan::Core::ScheduleTask`**

Create `lib/daan/core/schedule_task.rb`:

```ruby
# lib/daan/core/schedule_task.rb
module Daan
  module Core
    class ScheduleTask < RubyLLM::Tool
      include Daan::Core::Tool.module(timeout: 10.seconds)

      description "Schedule a one-shot task to fire a message to an agent at a future time. " \
                  "The agent will receive the message as a new conversation thread. " \
                  "Use this for deferred follow-ups such as 'check CI in 5 minutes' or " \
                  "'remind the team about the standup tomorrow morning'."

      param :agent_name, desc: "The agent who should receive the message (e.g. 'chief_of_staff', 'developer')"
      param :message,    desc: "The message to send to the agent when the task fires"
      param :run_at,     desc: "When to fire the task, as an ISO8601 datetime string (e.g. '2026-03-27T09:00:00+01:00')"

      def initialize(chat: nil, **)
        @chat = chat
      end

      def execute(agent_name:, message:, run_at:)
        Daan::AgentRegistry.find(agent_name)  # raises AgentNotFoundError if not found

        parsed_run_at = begin
          Time.iso8601(run_at)
        rescue ArgumentError, TypeError
          return "Error: '#{run_at}' is not a valid ISO8601 datetime string."
        end

        task = ScheduledTask.create!(
          agent_name:     agent_name,
          message:        message,
          task_type:      :one_shot,
          run_at:         parsed_run_at,
          source_chat_id: @chat&.id,
          enabled:        true
        )

        "Scheduled task ##{task.id} created. Agent '#{agent_name}' will receive the message at #{parsed_run_at.iso8601}."
      rescue Daan::AgentNotFoundError
        "Error: agent '#{agent_name}' not found in the registry."
      end
    end
  end
end
```

- [ ] **Step 4: Run the tool tests to confirm they pass**

```bash
bin/rails test test/lib/daan/core/schedule_task_test.rb
```

Expected: all pass, 0 failures.

- [ ] **Step 5: Run the full suite**

```bash
bin/rails test
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add lib/daan/core/schedule_task.rb test/lib/daan/core/schedule_task_test.rb
git commit -m "feat: add ScheduleTask tool for agent self-scheduling of one-shot tasks"
```

---

## Task 5: Register `ScheduleTask` tool on agents

Agents declare their tools in `.md` frontmatter. Add `Daan::Core::ScheduleTask` to the `chief_of_staff` agent as the primary user-facing agent. Other agents (e.g. `developer`, `engineering_manager`) can be wired up the same way if they need it — this task handles `chief_of_staff` as the reference case.

**Files:**
- Modify: `lib/daan/core/agents/chief_of_staff.md`

- [ ] **Step 1: Add the tool to the frontmatter**

In `lib/daan/core/agents/chief_of_staff.md`, add `- Daan::Core::ScheduleTask` to the `tools:` list:

```yaml
tools:
  - Daan::Core::DelegateTask
  - Daan::Core::ListAgents
  - Daan::Core::CreateSteps
  - Daan::Core::UpdateStep
  - Daan::Core::ScheduleTask
  - SwarmMemory::Tools::MemoryWrite
  - SwarmMemory::Tools::MemoryRead
  - SwarmMemory::Tools::MemoryEdit
  - SwarmMemory::Tools::MemoryDelete
  - SwarmMemory::Tools::MemoryGlob
  - SwarmMemory::Tools::MemoryGrep
```

- [ ] **Step 2: Verify the agent loader parses the tool correctly**

```bash
bin/rails runner "Daan::AgentLoader.sync!('lib/daan/core/agents'); agent = Daan::AgentRegistry.find('chief_of_staff'); puts agent.base_tools.map(&:name).inspect"
```

Expected output includes `"Daan::Core::ScheduleTask"` in the array.

- [ ] **Step 3: Commit**

```bash
git add lib/daan/core/agents/chief_of_staff.md
git commit -m "feat: add ScheduleTask tool to chief_of_staff agent"
```

---

## Task 6: UI — one-shot section on the tasks index

The tasks index already shows recurring tasks. Add a "Scheduled once" section below it. Each row shows: message (truncated), target agent, fires at (formatted datetime), status (Pending / Fired), and a link to the originating chat when `source_chat` is set.

**Files:**
- Modify: `app/views/scheduled_tasks/index.html.erb`

- [ ] **Step 1: Write a system test**

Create `test/system/scheduled_tasks_one_shot_test.rb`:

```ruby
# test/system/scheduled_tasks_one_shot_test.rb
require "application_system_test_case"

class ScheduledTasksOneShotTest < ApplicationSystemTestCase
  setup do
    Daan::AgentRegistry.register(
      Daan::Agent.new(name: "chief_of_staff", display_name: "Chief of Staff",
                      model_name: "claude-haiku-4-5-20251001", system_prompt: "p", max_steps: 5)
    )
    @source_chat = Chat.create!(agent_name: "chief_of_staff")
  end

  test "shows one-shot tasks in a separate section" do
    ScheduledTask.create!(
      agent_name: "chief_of_staff",
      message: "Run the weekly report",
      task_type: :one_shot,
      run_at: 1.hour.from_now,
      source_chat: @source_chat,
      enabled: true
    )

    visit scheduled_tasks_path

    assert_selector "h2", text: /Scheduled once/i
    assert_text "Run the weekly report"
    assert_text "Chief of Staff"
  end

  test "one-shot section shows Pending status for enabled tasks" do
    ScheduledTask.create!(
      agent_name: "chief_of_staff",
      message: "Pending task",
      task_type: :one_shot,
      run_at: 1.hour.from_now,
      enabled: true
    )

    visit scheduled_tasks_path

    within "[data-testid='one-shot-tasks']" do
      assert_text "Pending"
    end
  end

  test "one-shot section shows Fired status for disabled tasks" do
    ScheduledTask.create!(
      agent_name: "chief_of_staff",
      message: "Already fired",
      task_type: :one_shot,
      run_at: 10.minutes.ago,
      enabled: false
    )

    visit scheduled_tasks_path

    within "[data-testid='one-shot-tasks']" do
      assert_text "Fired"
    end
  end

  test "one-shot task row links to source chat when present" do
    ScheduledTask.create!(
      agent_name: "chief_of_staff",
      message: "Link check",
      task_type: :one_shot,
      run_at: 30.minutes.from_now,
      source_chat: @source_chat,
      enabled: true
    )

    visit scheduled_tasks_path

    within "[data-testid='one-shot-tasks']" do
      assert_selector "a[href*='/chat/threads/#{@source_chat.id}']"
    end
  end

  test "one-shot task row has no chat link when source_chat is nil" do
    ScheduledTask.create!(
      agent_name: "chief_of_staff",
      message: "No source",
      task_type: :one_shot,
      run_at: 30.minutes.from_now,
      source_chat: nil,
      enabled: true
    )

    visit scheduled_tasks_path

    within "[data-testid='one-shot-tasks']" do
      assert_text "No source"
      # Row must not contain a link to a chat thread
      assert_no_selector "a[href*='/chat/threads/']"
    end
  end

  test "recurring tasks section still renders when one-shot tasks exist" do
    ScheduledTask.create!(
      agent_name: "chief_of_staff",
      message: "daily",
      task_type: :recurring,
      schedule: "every day at 8am",
      timezone: "UTC",
      enabled: true
    )
    ScheduledTask.create!(
      agent_name: "chief_of_staff",
      message: "one shot",
      task_type: :one_shot,
      run_at: 1.hour.from_now,
      enabled: true
    )

    visit scheduled_tasks_path

    assert_selector "h2", text: /Recurring/i
    assert_selector "h2", text: /Scheduled once/i
  end
end
```

- [ ] **Step 2: Run the system test to confirm it fails**

```bash
bin/rails test:system test/system/scheduled_tasks_one_shot_test.rb
```

Expected: failures — "Scheduled once" section not rendered yet.

- [ ] **Step 3: Update the tasks index view**

In `app/views/scheduled_tasks/index.html.erb`, add the one-shot section below the existing recurring section. The `ScheduledTasksController#index` action must provide `@one_shot_tasks`; update it alongside the view.

Add to `app/controllers/scheduled_tasks_controller.rb`, inside `index`:

```ruby
@one_shot_tasks = ScheduledTask.where(task_type: :one_shot).order(run_at: :asc)
```

Add to `app/views/scheduled_tasks/index.html.erb` after the recurring tasks table:

```erb
<section class="mt-10">
  <h2 class="text-lg font-semibold text-gray-900 mb-4">Scheduled once</h2>

  <div data-testid="one-shot-tasks">
    <% if @one_shot_tasks.any? %>
      <table class="min-w-full divide-y divide-gray-200 text-sm">
        <thead>
          <tr>
            <th class="px-4 py-2 text-left text-gray-500 font-medium">Message</th>
            <th class="px-4 py-2 text-left text-gray-500 font-medium">Agent</th>
            <th class="px-4 py-2 text-left text-gray-500 font-medium">Fires at</th>
            <th class="px-4 py-2 text-left text-gray-500 font-medium">Status</th>
            <th class="px-4 py-2 text-left text-gray-500 font-medium">Origin</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-100">
          <% @one_shot_tasks.each do |task| %>
            <tr>
              <td class="px-4 py-2 text-gray-900 max-w-xs truncate">
                <%= task.message.truncate(80) %>
              </td>
              <td class="px-4 py-2 text-gray-700">
                <% agent_name = begin
                     Daan::AgentRegistry.find(task.agent_name)&.display_name
                   rescue Daan::AgentNotFoundError
                     task.agent_name
                   end %>
                <%= agent_name %>
              </td>
              <td class="px-4 py-2 text-gray-700">
                <%= task.run_at.strftime("%b %-d %Y, %H:%M %Z") %>
              </td>
              <td class="px-4 py-2">
                <% if task.enabled? %>
                  <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-yellow-100 text-yellow-800">Pending</span>
                <% else %>
                  <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-500">Fired</span>
                <% end %>
              </td>
              <td class="px-4 py-2 text-gray-700">
                <% if task.source_chat.present? %>
                  <%= link_to "View chat",
                        chat_thread_path(task.source_chat_id),
                        class: "text-indigo-600 hover:text-indigo-900 text-xs" %>
                <% else %>
                  <span class="text-gray-400 text-xs">—</span>
                <% end %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    <% else %>
      <p class="text-gray-400 text-sm">No one-shot tasks scheduled.</p>
    <% end %>
  </div>
</section>
```

- [ ] **Step 4: Run the system tests to confirm they pass**

```bash
bin/rails test:system test/system/scheduled_tasks_one_shot_test.rb
```

Expected: all pass, 0 failures.

- [ ] **Step 5: Run the full suite including system tests**

```bash
bin/rails test && bin/rails test:system
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/scheduled_tasks_controller.rb \
  app/views/scheduled_tasks/index.html.erb \
  test/system/scheduled_tasks_one_shot_test.rb
git commit -m "feat: add one-shot tasks section to scheduled tasks index page"
```

---

## Task 7: Final integration check

Run the complete test suite one final time to confirm everything passes together.

- [ ] **Step 1: Run the full suite**

```bash
bin/rails test && bin/rails test:system
```

Expected: all pass, 0 failures, 0 errors.

- [ ] **Step 2: Smoke-check in development**

Start the server and Solid Queue worker:

```bash
bin/rails server
bin/jobs start
```

In a conversation with the Chief of Staff, send:

> Schedule a message "Run the daily report" to yourself in 2 minutes.

Verify:
1. The agent calls `schedule_task` and returns a confirmation.
2. Visit `/scheduled_tasks` — a "Scheduled once" row appears with status "Pending" and a "View chat" link to the originating conversation.
3. After ~2 minutes, a new chat thread appears in the Chief of Staff's history with "Run the daily report" as the user message.
4. The row on `/scheduled_tasks` changes to status "Fired" (enabled becomes false).
