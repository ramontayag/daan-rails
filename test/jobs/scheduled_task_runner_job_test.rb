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

  test "raises AgentNotFoundError when agent_name is not registered" do
    task = ScheduledTask.create!(
      agent_name: "nonexistent_agent",
      message: "Do something",
      schedule: "every day at 8am",
      timezone: "UTC",
      enabled: true
    )
    assert_raises(Daan::AgentNotFoundError) do
      ScheduledTaskRunnerJob.perform_now(task)
    end
  end

  test "sets enabled to false on a one-shot task after firing" do
    task = ScheduledTask.create!(agent_name: "chief_of_staff", message: "ping",
                                 task_type: :one_shot, run_at: 1.minute.ago, enabled: true)

    ScheduledTaskRunnerJob.perform_now(task)

    assert_not task.reload.enabled, "expected one-shot task to be disabled after firing"
  end

  test "does not disable a recurring task after firing" do
    task = ScheduledTask.create!(agent_name: "chief_of_staff", message: "daily briefing",
                                 task_type: :recurring, schedule: "every day", timezone: "UTC",
                                 enabled: true)

    ScheduledTaskRunnerJob.perform_now(task)

    assert task.reload.enabled, "recurring task must remain enabled after firing"
  end
end
