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
