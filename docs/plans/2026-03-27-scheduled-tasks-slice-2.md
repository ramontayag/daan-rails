# Scheduled Tasks Slice 2: Recurring Tasks End-to-End — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build recurring scheduled tasks end-to-end: model, poller job, runner job, and CRUD UI.

**Architecture:** A single `ScheduledTaskPollerJob` is registered in `config/recurring.yml` to run every minute via Solid Queue. On each tick it queries all enabled recurring `ScheduledTask` records and uses fugit to check whether the most recent expected tick of each schedule is after `last_enqueued_at` (or `last_enqueued_at` is nil); if so it enqueues `ScheduledTaskRunnerJob` for that task and stamps `last_enqueued_at = Time.current`. This "stamp then forget" design means missed ticks fire at most once on recovery and never more than once per window. `ScheduledTaskRunnerJob` creates a new `Chat`, inserts an invisible system message, inserts the task's user message, and enqueues `LlmJob` — exactly mirroring how `Daan::CreateMessage` works but without the broadcast or auto-enqueue side effects on the invisible message.

**Tech Stack:** Rails 8.1, Minitest, fugit (already a Solid Queue dependency), Solid Queue recurring.yml

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `db/migrate/TIMESTAMP_create_scheduled_tasks.rb` | Schema for `scheduled_tasks` table |
| Create | `app/models/scheduled_task.rb` | Model with validations and `due?` helper |
| Create | `app/jobs/scheduled_task_poller_job.rb` | Queries enabled tasks, enqueues runner if due |
| Create | `app/jobs/scheduled_task_runner_job.rb` | Creates Chat + messages + enqueues LlmJob |
| Modify | `config/recurring.yml` | Register `ScheduledTaskPollerJob` every minute |
| Create | `app/controllers/scheduled_tasks_controller.rb` | CRUD: index, new, create, edit, update, destroy |
| Modify | `config/routes.rb` | `resources :scheduled_tasks` |
| Create | `app/views/scheduled_tasks/index.html.erb` | List with enabled toggle |
| Create | `app/views/scheduled_tasks/new.html.erb` | New task form |
| Create | `app/views/scheduled_tasks/edit.html.erb` | Edit task form |
| Create | `app/views/scheduled_tasks/_form.html.erb` | Shared form partial |
| Create | `app/javascript/controllers/timezone_controller.js` | Captures browser TZ into hidden field |
| Create | `test/models/scheduled_task_test.rb` | Unit tests for model + `due?` |
| Create | `test/jobs/scheduled_task_poller_job_test.rb` | Unit tests for poller |
| Create | `test/jobs/scheduled_task_runner_job_test.rb` | Unit tests for runner |
| Create | `test/fixtures/scheduled_tasks.yml` | Fixture records |
| Create | `test/integration/scheduled_tasks_flow_test.rb` | Controller integration tests |

---

## Step 1 — Migration

- [ ] Generate and write the migration.

```ruby
# db/migrate/TIMESTAMP_create_scheduled_tasks.rb
class CreateScheduledTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :scheduled_tasks do |t|
      t.string   :agent_name,       null: false
      t.text     :message,          null: false
      t.string   :schedule,         null: false
      t.string   :timezone,         null: false, default: "UTC"
      t.datetime :last_enqueued_at
      t.boolean  :enabled,          null: false, default: true

      t.timestamps
    end

    add_index :scheduled_tasks, :agent_name
    add_index :scheduled_tasks, :enabled
  end
end
```

- [ ] Run the migration.

```
bin/rails db:migrate
```

Expected output: `== CreateScheduledTasks: migrated`

---

## Step 2 — Fixtures

- [ ] Write fixtures.

```yaml
# test/fixtures/scheduled_tasks.yml
daily_digest:
  agent_name: chief_of_staff
  message: "Please send the daily digest."
  schedule: "every day at 8am"
  timezone: "America/New_York"
  last_enqueued_at:
  enabled: true

disabled_task:
  agent_name: chief_of_staff
  message: "This task is disabled."
  schedule: "every day at 9am"
  timezone: "UTC"
  last_enqueued_at:
  enabled: false

already_fired_today:
  agent_name: chief_of_staff
  message: "Already ran today."
  schedule: "every day at 8am"
  timezone: "UTC"
  last_enqueued_at: <%= 1.hour.ago.iso8601 %>
  enabled: true
```

---

## Step 3 — Model (test first)

- [ ] Write the failing test.

```ruby
# test/models/scheduled_task_test.rb
require "test_helper"

class ScheduledTaskTest < ActiveSupport::TestCase
  test "valid with required attributes" do
    task = ScheduledTask.new(
      agent_name: "chief_of_staff",
      message: "Do the thing",
      schedule: "every day at 8am",
      timezone: "America/New_York"
    )
    assert task.valid?
  end

  test "invalid without agent_name" do
    task = ScheduledTask.new(message: "Do the thing", schedule: "every day at 8am", timezone: "UTC")
    assert_not task.valid?
    assert_includes task.errors[:agent_name], "can't be blank"
  end

  test "invalid without message" do
    task = ScheduledTask.new(agent_name: "chief_of_staff", schedule: "every day at 8am", timezone: "UTC")
    assert_not task.valid?
    assert_includes task.errors[:message], "can't be blank"
  end

  test "invalid without schedule" do
    task = ScheduledTask.new(agent_name: "chief_of_staff", message: "Do the thing", timezone: "UTC")
    assert_not task.valid?
    assert_includes task.errors[:schedule], "can't be blank"
  end

  test "invalid with unparseable schedule" do
    task = ScheduledTask.new(
      agent_name: "chief_of_staff",
      message: "Do the thing",
      schedule: "not a real schedule !!!",
      timezone: "UTC"
    )
    assert_not task.valid?
    assert_includes task.errors[:schedule], "is not a valid schedule"
  end

  test "invalid without timezone" do
    task = ScheduledTask.new(agent_name: "chief_of_staff", message: "Do the thing", schedule: "every day at 8am")
    task.timezone = nil
    assert_not task.valid?
    assert_includes task.errors[:timezone], "can't be blank"
  end

  test "enabled defaults to true" do
    task = ScheduledTask.create!(
      agent_name: "chief_of_staff",
      message: "Do the thing",
      schedule: "every day at 8am",
      timezone: "UTC"
    )
    assert task.enabled?
  end

  test "due? returns true when last_enqueued_at is nil" do
    task = ScheduledTask.new(
      agent_name: "chief_of_staff",
      message: "Do the thing",
      schedule: "every day at 8am",
      timezone: "UTC",
      last_enqueued_at: nil
    )
    assert task.due?
  end

  test "due? returns false when most recent expected tick is before last_enqueued_at" do
    # last fired 30 minutes ago; next daily tick is still in the future
    task = ScheduledTask.new(
      agent_name: "chief_of_staff",
      message: "Do the thing",
      schedule: "every day at 8am",
      timezone: "UTC",
      last_enqueued_at: 30.minutes.ago
    )
    # Stub Time.current so the test is stable regardless of time of day
    travel_to Time.zone.parse("2026-03-27 08:15:00 UTC") do
      task.last_enqueued_at = Time.current - 10.minutes  # fired at 08:05
      assert_not task.due?
    end
  end

  test "due? returns true when most recent expected tick is after last_enqueued_at" do
    travel_to Time.zone.parse("2026-03-27 09:00:00 UTC") do
      task = ScheduledTask.new(
        agent_name: "chief_of_staff",
        message: "Do the thing",
        schedule: "every day at 8am",
        timezone: "UTC",
        last_enqueued_at: Time.zone.parse("2026-03-26 08:00:00 UTC")  # yesterday
      )
      assert task.due?
    end
  end

  test "enabled scope returns only enabled tasks" do
    assert_includes ScheduledTask.enabled, scheduled_tasks(:daily_digest)
    assert_not_includes ScheduledTask.enabled, scheduled_tasks(:disabled_task)
  end
end
```

- [ ] Run tests (expect failures).

```
bin/rails test test/models/scheduled_task_test.rb
```

Expected: multiple failures — `ScheduledTask` does not exist yet.

- [ ] Write the model.

```ruby
# app/models/scheduled_task.rb
class ScheduledTask < ApplicationRecord
  validates :agent_name, presence: true
  validates :message,    presence: true
  validates :schedule,   presence: true
  validates :timezone,   presence: true
  validate  :schedule_must_be_parseable

  scope :enabled, -> { where(ScheduledTask.arel_table[:enabled].eq(true)) }

  # Returns true if the most recent expected tick of the cron schedule is
  # after last_enqueued_at (or last_enqueued_at is nil), meaning the task
  # is due to fire.
  def due?
    cron = Fugit.parse(schedule)
    return false unless cron

    now = Time.current
    # previous_time returns the most recent tick at or before `now`
    last_tick = cron.previous_time(now)
    return true if last_enqueued_at.nil?

    last_tick.to_t > last_enqueued_at
  end

  private

  def schedule_must_be_parseable
    return if schedule.blank?
    errors.add(:schedule, "is not a valid schedule") unless Fugit.parse(schedule)
  end
end
```

- [ ] Run tests (expect green).

```
bin/rails test test/models/scheduled_task_test.rb
```

Expected: all tests pass.

---

## Step 4 — ScheduledTaskRunnerJob (test first)

- [ ] Write the failing test.

```ruby
# test/jobs/scheduled_task_runner_job_test.rb
require "test_helper"

class ScheduledTaskRunnerJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
    @task = ScheduledTask.create!(
      agent_name: "chief_of_staff",
      message: "Run the daily digest",
      schedule: "every day at 8am",
      timezone: "UTC",
      enabled: true
    )
  end

  test "creates a new Chat for the target agent" do
    assert_difference "Chat.count", 1 do
      ScheduledTaskRunnerJob.perform_now(@task)
    end
    chat = Chat.where(agent_name: "chief_of_staff").last
    assert_equal "chief_of_staff", chat.agent_name
  end

  test "prepends an invisible system message" do
    ScheduledTaskRunnerJob.perform_now(@task)
    chat = Chat.where(agent_name: "chief_of_staff").last
    system_messages = chat.messages.where(role: "system", visible: false)
    assert_equal 1, system_messages.count
    assert_includes system_messages.first.content,
                    "started automatically by a scheduled task"
  end

  test "creates a visible user message from task.message" do
    ScheduledTaskRunnerJob.perform_now(@task)
    chat = Chat.where(agent_name: "chief_of_staff").last
    user_messages = chat.messages.where(role: "user")
    assert_equal 1, user_messages.count
    assert_equal "Run the daily digest", user_messages.first.content
  end

  test "enqueues LlmJob for the new chat" do
    assert_enqueued_with(job: LlmJob) do
      ScheduledTaskRunnerJob.perform_now(@task)
    end
  end

  test "system message is created before user message" do
    ScheduledTaskRunnerJob.perform_now(@task)
    chat = Chat.where(agent_name: "chief_of_staff").last
    messages = chat.messages.order(:id)
    assert_equal "system", messages.first.role
    assert_equal "user",   messages.second.role
  end
end
```

- [ ] Run tests (expect failures).

```
bin/rails test test/jobs/scheduled_task_runner_job_test.rb
```

Expected: multiple failures — `ScheduledTaskRunnerJob` does not exist yet.

- [ ] Write the job.

```ruby
# app/jobs/scheduled_task_runner_job.rb
class ScheduledTaskRunnerJob < ApplicationJob
  queue_as :default

  def perform(task)
    agent = Daan::AgentRegistry.find(task.agent_name)
    chat  = Chat.create!(agent_name: agent.name, model: agent.model_name)

    # Invisible system message so ConversationRunner knows this was auto-started.
    chat.messages.create!(
      role: "system",
      content: "This conversation was started automatically by a scheduled task.",
      visible: false
    )

    # Visible user message — the actual task payload.
    chat.messages.create!(role: "user", content: task.message, visible: true)

    LlmJob.perform_later(chat)
  end
end
```

Note: `Chat.create!` uses `model:` with the agent's model name string, matching the pattern in `ThreadsController#create`. The invisible system message is inserted directly (no `Daan::CreateMessage`) because `CreateMessage` broadcasts and auto-enqueues `LlmJob` on user messages — both side effects are wrong here.

- [ ] Run tests (expect green).

```
bin/rails test test/jobs/scheduled_task_runner_job_test.rb
```

Expected: all tests pass.

---

## Step 5 — ScheduledTaskPollerJob (test first)

- [ ] Write the failing test.

```ruby
# test/jobs/scheduled_task_poller_job_test.rb
require "test_helper"

class ScheduledTaskPollerJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    ScheduledTask.destroy_all
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
  end

  test "enqueues ScheduledTaskRunnerJob for each due task" do
    due_task = ScheduledTask.create!(
      agent_name: "chief_of_staff",
      message: "Daily digest",
      schedule: "every day at 8am",
      timezone: "UTC",
      enabled: true,
      last_enqueued_at: nil
    )

    assert_enqueued_with(job: ScheduledTaskRunnerJob, args: [due_task]) do
      ScheduledTaskPollerJob.perform_now
    end
  end

  test "stamps last_enqueued_at on due tasks" do
    task = ScheduledTask.create!(
      agent_name: "chief_of_staff",
      message: "Daily digest",
      schedule: "every day at 8am",
      timezone: "UTC",
      enabled: true,
      last_enqueued_at: nil
    )

    freeze_time do
      ScheduledTaskPollerJob.perform_now
      assert_in_delta Time.current.to_f, task.reload.last_enqueued_at.to_f, 1.0
    end
  end

  test "does not enqueue for disabled tasks" do
    ScheduledTask.create!(
      agent_name: "chief_of_staff",
      message: "Disabled task",
      schedule: "every day at 8am",
      timezone: "UTC",
      enabled: false,
      last_enqueued_at: nil
    )

    assert_no_enqueued_jobs(only: ScheduledTaskRunnerJob) do
      ScheduledTaskPollerJob.perform_now
    end
  end

  test "does not enqueue when task is not due" do
    travel_to Time.zone.parse("2026-03-27 09:00:00 UTC") do
      task = ScheduledTask.create!(
        agent_name: "chief_of_staff",
        message: "Daily digest",
        schedule: "every day at 8am",
        timezone: "UTC",
        enabled: true,
        last_enqueued_at: Time.zone.parse("2026-03-27 08:01:00 UTC")
      )

      assert_no_enqueued_jobs(only: ScheduledTaskRunnerJob) do
        ScheduledTaskPollerJob.perform_now
      end

      assert_in_delta Time.zone.parse("2026-03-27 08:01:00 UTC").to_f,
                      task.reload.last_enqueued_at.to_f, 1.0
    end
  end

  test "only fires once even if multiple ticks were missed" do
    # Task should have fired at 8am and 8am the day before, but last_enqueued_at
    # is from two days ago — it must only enqueue once, not twice.
    travel_to Time.zone.parse("2026-03-27 09:00:00 UTC") do
      ScheduledTask.create!(
        agent_name: "chief_of_staff",
        message: "Daily digest",
        schedule: "every day at 8am",
        timezone: "UTC",
        enabled: true,
        last_enqueued_at: Time.zone.parse("2026-03-25 08:00:00 UTC")
      )

      assert_enqueued_jobs(1, only: ScheduledTaskRunnerJob) do
        ScheduledTaskPollerJob.perform_now
      end
    end
  end
end
```

- [ ] Run tests (expect failures).

```
bin/rails test test/jobs/scheduled_task_poller_job_test.rb
```

Expected: multiple failures — `ScheduledTaskPollerJob` does not exist yet.

- [ ] Write the job.

```ruby
# app/jobs/scheduled_task_poller_job.rb
class ScheduledTaskPollerJob < ApplicationJob
  queue_as :background

  def perform
    ScheduledTask.enabled.each do |task|
      next unless task.due?

      ScheduledTaskRunnerJob.perform_later(task)
      task.update_column(:last_enqueued_at, Time.current)
    rescue => e
      Rails.logger.error(
        "[ScheduledTaskPollerJob] task_id=#{task.id} error=#{e.class}: #{e.message}"
      )
      # R6: silent failure — log and continue to next task
    end
  end
end
```

- [ ] Run tests (expect green).

```
bin/rails test test/jobs/scheduled_task_poller_job_test.rb
```

Expected: all tests pass.

---

## Step 6 — Register poller in recurring.yml

- [ ] Edit `config/recurring.yml`.

```yaml
# config/recurring.yml
production:
  clear_solid_queue_finished_jobs:
    command: "SolidQueue::Job.clear_finished_in_batches(sleep_between_batches: 0.3)"
    schedule: every hour at minute 12

  scheduled_task_poller:
    class: ScheduledTaskPollerJob
    queue: background
    schedule: every minute
```

No test is needed for this file — it is declarative Solid Queue configuration. Its correctness is validated by the end-to-end demo.

**Note for development:** `recurring.yml` only fires in the `production:` block. In development, trigger the poller manually: `bin/rails runner 'ScheduledTaskPollerJob.perform_now'`

---

## Step 7 — Routes

- [ ] Edit `config/routes.rb`.

```ruby
# config/routes.rb
Rails.application.routes.draw do
  if Rails.env.development?
    mount Lookbook::Engine, at: "/rails/lookbook"
  end

  root "chats#index"
  get "chat", to: "chats#index", as: :chat

  scope "chat", as: "chat" do
    resources :agents, only: [ :show ], param: :name, path: "agents", controller: "chats" do
      resources :threads, only: [ :show, :create ], shallow: true do
        resources :messages, only: [ :create ]
      end
    end
  end

  resources :scheduled_tasks

  resources :documents, only: [ :show ]

  get "up" => "rails/health#show", as: :rails_health_check
end
```

---

## Step 8 — Controller (test first)

- [ ] Write the failing integration test.

```ruby
# test/integration/scheduled_tasks_flow_test.rb
require "test_helper"

class ScheduledTasksFlowTest < ActionDispatch::IntegrationTest
  setup do
    ScheduledTask.destroy_all
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
  end

  # ---- index ----

  test "index renders a list of scheduled tasks" do
    ScheduledTask.create!(agent_name: "chief_of_staff", message: "Digest",
                          schedule: "every day at 8am", timezone: "UTC")

    get scheduled_tasks_path
    assert_response :success
    assert_select "[data-testid='scheduled-task-row']", 1
  end

  test "index shows enabled and disabled tasks" do
    ScheduledTask.create!(agent_name: "chief_of_staff", message: "A",
                          schedule: "every day at 8am", timezone: "UTC", enabled: true)
    ScheduledTask.create!(agent_name: "chief_of_staff", message: "B",
                          schedule: "every day at 9am", timezone: "UTC", enabled: false)

    get scheduled_tasks_path
    assert_response :success
    assert_select "[data-testid='scheduled-task-row']", 2
  end

  # ---- new / create ----

  test "new renders the form" do
    get new_scheduled_task_path
    assert_response :success
    assert_select "form[action='#{scheduled_tasks_path}']"
  end

  test "create with valid params redirects to index" do
    assert_difference "ScheduledTask.count", 1 do
      post scheduled_tasks_path, params: {
        scheduled_task: {
          agent_name: "chief_of_staff",
          message: "Daily digest",
          schedule: "every day at 8am",
          timezone: "America/New_York"
        }
      }
    end
    assert_redirected_to scheduled_tasks_path
  end

  test "create with invalid schedule re-renders form" do
    assert_no_difference "ScheduledTask.count" do
      post scheduled_tasks_path, params: {
        scheduled_task: {
          agent_name: "chief_of_staff",
          message: "Daily digest",
          schedule: "not a schedule",
          timezone: "UTC"
        }
      }
    end
    assert_response :unprocessable_entity
  end

  test "create with missing agent_name re-renders form" do
    assert_no_difference "ScheduledTask.count" do
      post scheduled_tasks_path, params: {
        scheduled_task: {
          agent_name: "",
          message: "Daily digest",
          schedule: "every day at 8am",
          timezone: "UTC"
        }
      }
    end
    assert_response :unprocessable_entity
  end

  # ---- edit / update ----

  test "edit renders the form" do
    task = ScheduledTask.create!(agent_name: "chief_of_staff", message: "A",
                                 schedule: "every day at 8am", timezone: "UTC")
    get edit_scheduled_task_path(task)
    assert_response :success
    assert_select "form[action='#{scheduled_task_path(task)}']"
  end

  test "update with valid params redirects to index" do
    task = ScheduledTask.create!(agent_name: "chief_of_staff", message: "Old",
                                 schedule: "every day at 8am", timezone: "UTC")
    patch scheduled_task_path(task), params: {
      scheduled_task: { message: "New message", timezone: "America/Chicago" }
    }
    assert_redirected_to scheduled_tasks_path
    assert_equal "New message", task.reload.message
    assert_equal "America/Chicago", task.reload.timezone
  end

  test "update with invalid schedule re-renders form" do
    task = ScheduledTask.create!(agent_name: "chief_of_staff", message: "Old",
                                 schedule: "every day at 8am", timezone: "UTC")
    patch scheduled_task_path(task), params: {
      scheduled_task: { schedule: "garbage" }
    }
    assert_response :unprocessable_entity
    assert_equal "every day at 8am", task.reload.schedule
  end

  # ---- destroy ----

  test "destroy deletes the record and redirects to index" do
    task = ScheduledTask.create!(agent_name: "chief_of_staff", message: "A",
                                 schedule: "every day at 8am", timezone: "UTC")
    assert_difference "ScheduledTask.count", -1 do
      delete scheduled_task_path(task)
    end
    assert_redirected_to scheduled_tasks_path
  end

  # ---- toggle enabled ----

  test "update can toggle enabled to false" do
    task = ScheduledTask.create!(agent_name: "chief_of_staff", message: "A",
                                 schedule: "every day at 8am", timezone: "UTC", enabled: true)
    patch scheduled_task_path(task), params: {
      scheduled_task: { enabled: false }
    }
    assert_redirected_to scheduled_tasks_path
    assert_not task.reload.enabled?
  end

  test "update can toggle enabled to true" do
    task = ScheduledTask.create!(agent_name: "chief_of_staff", message: "A",
                                 schedule: "every day at 8am", timezone: "UTC", enabled: false)
    patch scheduled_task_path(task), params: {
      scheduled_task: { enabled: true }
    }
    assert_redirected_to scheduled_tasks_path
    assert task.reload.enabled?
  end
end
```

- [ ] Run tests (expect failures).

```
bin/rails test test/integration/scheduled_tasks_flow_test.rb
```

Expected: multiple failures — controller and routes not yet created.

- [ ] Write the controller.

```ruby
# app/controllers/scheduled_tasks_controller.rb
class ScheduledTasksController < ApplicationController
  before_action :set_task, only: [ :edit, :update, :destroy ]

  def index
    @tasks = ScheduledTask.order(created_at: :desc)
  end

  def new
    @task = ScheduledTask.new
  end

  def create
    @task = ScheduledTask.new(task_params)
    if @task.save
      redirect_to scheduled_tasks_path, notice: "Scheduled task created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @task.update(task_params)
      redirect_to scheduled_tasks_path, notice: "Scheduled task updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @task.destroy!
    redirect_to scheduled_tasks_path, notice: "Scheduled task deleted."
  end

  private

  def set_task
    @task = ScheduledTask.find(params[:id])
  end

  def task_params
    params.require(:scheduled_task).permit(
      :agent_name, :message, :schedule, :timezone, :enabled
    )
  end
end
```

- [ ] Run tests (expect green).

```
bin/rails test test/integration/scheduled_tasks_flow_test.rb
```

Expected: all tests pass.

---

## Step 9 — Timezone Stimulus controller

The form needs to capture the browser timezone into a hidden field before submit. This is a small Stimulus controller.

- [ ] Write the controller.

```javascript
// app/javascript/controllers/timezone_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["field"]

  connect() {
    this.fieldTarget.value = Intl.DateTimeFormat().resolvedOptions().timeZone
  }
}
```

The `index.js` auto-loader already registers all `*_controller.js` files via `eagerLoadControllersFrom`, so no manual registration is needed.

---

## Step 10 — Views

- [ ] Write the shared form partial.

```erb
<%# app/views/scheduled_tasks/_form.html.erb %>
<%= form_with model: task,
      data: { controller: "timezone", testid: "scheduled-task-form" } do |f| %>

  <%# Hidden timezone field — populated by the timezone Stimulus controller %>
  <%= f.hidden_field :timezone,
        data: { timezone_target: "field" },
        value: task.timezone.presence || "UTC" %>

  <% if task.errors.any? %>
    <div class="mb-4 p-3 bg-red-50 border border-red-200 rounded text-sm text-red-700">
      <ul class="list-disc pl-4">
        <% task.errors.full_messages.each do |msg| %>
          <li><%= msg %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <div class="mb-4">
    <%= f.label :agent_name, "Agent", class: "block text-sm font-medium text-gray-700 mb-1" %>
    <%= f.select :agent_name,
          Daan::AgentRegistry.all.map { |a| [a.display_name, a.name] },
          { prompt: "Select an agent" },
          class: "w-full border border-gray-300 rounded px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" %>
  </div>

  <div class="mb-4">
    <%= f.label :schedule, "Schedule", class: "block text-sm font-medium text-gray-700 mb-1" %>
    <%= f.text_field :schedule,
          placeholder: "every day at 8am",
          class: "w-full border border-gray-300 rounded px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" %>
    <p class="mt-1 text-xs text-gray-500">Human-readable cron (e.g. "every day at 8am", "every monday at 9am")</p>
  </div>

  <div class="mb-4">
    <%= f.label :message, "Message", class: "block text-sm font-medium text-gray-700 mb-1" %>
    <%= f.text_area :message,
          rows: 4,
          placeholder: "What should the agent do?",
          class: "w-full border border-gray-300 rounded px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" %>
  </div>

  <div class="mb-6 flex items-center gap-2">
    <%= f.check_box :enabled,
          class: "h-4 w-4 text-blue-600 border-gray-300 rounded" %>
    <%= f.label :enabled, "Enabled", class: "text-sm text-gray-700" %>
  </div>

  <div class="flex gap-3">
    <%= f.submit class: "px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded hover:bg-blue-700 cursor-pointer" %>
    <%= link_to "Cancel", scheduled_tasks_path,
          class: "px-4 py-2 text-sm text-gray-600 hover:text-gray-900" %>
  </div>
<% end %>
```

- [ ] Write the index view.

```erb
<%# app/views/scheduled_tasks/index.html.erb %>
<div class="max-w-4xl mx-auto p-6">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-xl font-semibold text-gray-900">Scheduled Tasks</h1>
    <%= link_to "New task", new_scheduled_task_path,
          class: "px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded hover:bg-blue-700" %>
  </div>

  <% if @tasks.empty? %>
    <p class="text-gray-500 text-sm">No scheduled tasks yet.</p>
  <% else %>
    <div class="overflow-x-auto">
      <table class="w-full text-sm text-left">
        <thead class="text-xs text-gray-500 uppercase border-b border-gray-200">
          <tr>
            <th class="py-2 pr-4">Agent</th>
            <th class="py-2 pr-4">Schedule</th>
            <th class="py-2 pr-4">Timezone</th>
            <th class="py-2 pr-4">Last fired</th>
            <th class="py-2 pr-4">Enabled</th>
            <th class="py-2"></th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-100">
          <% @tasks.each do |task| %>
            <tr data-testid="scheduled-task-row">
              <td class="py-3 pr-4 font-medium text-gray-900"><%= task.agent_name %></td>
              <td class="py-3 pr-4 text-gray-700"><%= task.schedule %></td>
              <td class="py-3 pr-4 text-gray-500"><%= task.timezone %></td>
              <td class="py-3 pr-4 text-gray-500">
                <%= task.last_enqueued_at ? task.last_enqueued_at.strftime("%b %-d %H:%M") : "Never" %>
              </td>
              <td class="py-3 pr-4">
                <%= form_with url: scheduled_task_path(task), method: :patch,
                              data: { turbo_submits_with: "" } do |f| %>
                  <%= f.check_box :enabled,
                        { checked: task.enabled?,
                          onchange: "this.form.requestSubmit()",
                          class: "h-4 w-4 text-blue-600 border-gray-300 rounded cursor-pointer" },
                        "1", "0",
                        name: "scheduled_task[enabled]" %>
                <% end %>
              </td>
              <td class="py-3 text-right whitespace-nowrap">
                <%= link_to "Edit", edit_scheduled_task_path(task),
                      class: "text-blue-600 hover:underline mr-3" %>
                <%= button_to "Delete", scheduled_task_path(task), method: :delete,
                      class: "text-red-500 hover:underline bg-transparent border-none cursor-pointer p-0",
                      data: { turbo_confirm: "Delete this scheduled task?" } %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
  <% end %>
</div>
```

- [ ] Write the new view.

```erb
<%# app/views/scheduled_tasks/new.html.erb %>
<div class="max-w-xl mx-auto p-6">
  <div class="mb-6">
    <h1 class="text-xl font-semibold text-gray-900">New Scheduled Task</h1>
  </div>
  <%= render "form", task: @task %>
</div>
```

- [ ] Write the edit view.

```erb
<%# app/views/scheduled_tasks/edit.html.erb %>
<div class="max-w-xl mx-auto p-6">
  <div class="mb-6">
    <h1 class="text-xl font-semibold text-gray-900">Edit Scheduled Task</h1>
  </div>
  <%= render "form", task: @task %>
</div>
```

---

## Step 11 — Full test suite

- [ ] Run the full test suite.

```
bin/rails test && bin/rails test:system
```

Expected: all tests pass, no regressions.

---

## Step 12 — Commit

- [ ] Stage and commit all new files.

```
git add \
  db/migrate/*_create_scheduled_tasks.rb \
  app/models/scheduled_task.rb \
  app/jobs/scheduled_task_poller_job.rb \
  app/jobs/scheduled_task_runner_job.rb \
  config/recurring.yml \
  app/controllers/scheduled_tasks_controller.rb \
  config/routes.rb \
  app/views/scheduled_tasks/index.html.erb \
  app/views/scheduled_tasks/new.html.erb \
  app/views/scheduled_tasks/edit.html.erb \
  "app/views/scheduled_tasks/_form.html.erb" \
  app/javascript/controllers/timezone_controller.js \
  test/models/scheduled_task_test.rb \
  test/jobs/scheduled_task_poller_job_test.rb \
  test/jobs/scheduled_task_runner_job_test.rb \
  test/fixtures/scheduled_tasks.yml \
  test/integration/scheduled_tasks_flow_test.rb \
  db/schema.rb
```

```
git commit -m "$(cat <<'EOF'
feat: add recurring scheduled tasks end-to-end (Slice 2)

- ScheduledTask model with fugit-backed due? helper and schedule validation
- ScheduledTaskPollerJob registered in recurring.yml (every minute); stamps
  last_enqueued_at after each enqueue so at most one fire per schedule window
- ScheduledTaskRunnerJob creates a new Chat with an invisible system message
  and the task's user message, then enqueues LlmJob
- CRUD UI: index with inline enabled toggle, new/edit forms with browser
  timezone capture via a timezone Stimulus controller

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Self-review checklist

- [x] Every code step includes exact code — no placeholders
- [x] Every test step includes actual test code
- [x] Every run step includes exact command and expected output
- [x] TDD order respected throughout: failing test → implementation → green
- [x] `bin/rails test && bin/rails test:system` used for full suite run
- [x] Scopes use Arel (`ScheduledTask.arel_table[:enabled].eq(true)`), not SQL strings
- [x] R3 satisfied: schedule stored as human-readable string, parsed by fugit
- [x] R7 satisfied: timezone captured via `Intl.DateTimeFormat().resolvedOptions().timeZone` in timezone Stimulus controller
- [x] R8 satisfied: `ScheduledTaskPollerJob` registered in `config/recurring.yml`
- [x] R9 satisfied: no reference to `SolidQueue::` AR models in business logic
- [x] R11 satisfied: `due?` checks `last_tick > last_enqueued_at`; only one enqueue per `perform` call per task regardless of missed ticks
- [x] R6 satisfied: poller rescues and logs errors per-task, continues to next
- [x] `Chat.create!` uses `model: agent.model_name` — consistent with `ThreadsController#create`
- [x] Invisible system message inserted directly via `chat.messages.create!` — avoids `Daan::CreateMessage`'s broadcast and auto-LlmJob side effects
- [x] No new system tests added — all coverage is unit + integration (consistent with existing test structure for non-interactive flows)
