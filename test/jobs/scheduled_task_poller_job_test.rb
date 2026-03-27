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

    assert_enqueued_with(job: ScheduledTaskRunnerJob, args: [ due_task ]) do
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
