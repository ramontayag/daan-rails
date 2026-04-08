require "test_helper"

class Daan::Core::ScheduleTaskTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    RubyLLM::Models.instance.load_from_json!
    Daan::Core::AgentRegistry.register(
      Daan::Core::Agent.new(name: "chief_of_staff", display_name: "Chief of Staff",
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
    assert ScheduledTask.last.one_shot?
  end

  test "sets the correct agent_name on the created task" do
    @tool.execute(agent_name: "chief_of_staff", message: "Run the daily report", run_at: 5.minutes.from_now.iso8601)
    assert_equal "chief_of_staff", ScheduledTask.last.agent_name
  end

  test "sets the correct message on the created task" do
    @tool.execute(agent_name: "chief_of_staff", message: "Run the daily report", run_at: 5.minutes.from_now.iso8601)
    assert_equal "Run the daily report", ScheduledTask.last.message
  end

  test "sets run_at from ISO8601 string on the created task" do
    future = 5.minutes.from_now
    @tool.execute(agent_name: "chief_of_staff", message: "ping", run_at: future.iso8601)
    assert_in_delta future.to_i, ScheduledTask.last.run_at.to_i, 1
  end

  test "sets source_chat_id to the current chat's id" do
    @tool.execute(agent_name: "chief_of_staff", message: "ping", run_at: 5.minutes.from_now.iso8601)
    assert_equal @chat.id, ScheduledTask.last.source_chat_id
  end

  test "creates the task with enabled: true" do
    @tool.execute(agent_name: "chief_of_staff", message: "ping", run_at: 5.minutes.from_now.iso8601)
    assert ScheduledTask.last.enabled
  end

  test "returns a confirmation string containing the agent name and run_at" do
    future = 5.minutes.from_now
    result = @tool.execute(agent_name: "chief_of_staff", message: "ping", run_at: future.iso8601)
    assert_includes result, "chief_of_staff"
    assert_kind_of String, result
  end

  test "returns an error string when agent_name is not in the registry" do
    result = @tool.execute(agent_name: "ghost_agent", message: "ping", run_at: 5.minutes.from_now.iso8601)
    assert_match(/[Ee]rror/, result)
    assert_not_includes result, "Scheduled"
  end

  test "returns an error string when run_at is not a valid ISO8601 string" do
    result = @tool.execute(agent_name: "chief_of_staff", message: "ping", run_at: "not-a-date")
    assert_match(/[Ee]rror/, result)
  end

  test "does not create a task when agent_name is unknown" do
    assert_no_difference "ScheduledTask.count" do
      @tool.execute(agent_name: "ghost_agent", message: "ping", run_at: 5.minutes.from_now.iso8601)
    end
  end

  test "does not create a task when run_at is invalid" do
    assert_no_difference "ScheduledTask.count" do
      @tool.execute(agent_name: "chief_of_staff", message: "ping", run_at: "bad")
    end
  end
end
