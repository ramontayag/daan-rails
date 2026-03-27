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
    due      = ScheduledTask.create!(agent_name: "chief_of_staff", message: "due",
                                     task_type: :one_shot, run_at: 1.minute.ago, enabled: true)
    _future  = ScheduledTask.create!(agent_name: "chief_of_staff", message: "future",
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
end
