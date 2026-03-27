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
    travel_to Time.zone.parse("2026-03-27 08:15:00 UTC") do
      task = ScheduledTask.new(
        agent_name: "chief_of_staff",
        message: "Do the thing",
        schedule: "every day at 8am",
        timezone: "UTC",
        last_enqueued_at: Time.current - 10.minutes  # fired at 08:05
      )
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
