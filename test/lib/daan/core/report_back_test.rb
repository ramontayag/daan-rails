# test/lib/daan/core/report_back_test.rb
require "test_helper"

class Daan::Core::ReportBackTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Daan::Core::AgentRegistry.register(
      Daan::Core::Agent.new(name: "chief_of_staff", display_name: "Chief of Staff",
                      model_name: "m", system_prompt: "p", max_steps: 10)
    )
    Daan::Core::AgentRegistry.register(
      Daan::Core::Agent.new(name: "engineering_manager", display_name: "Engineering Manager",
                      model_name: "m", system_prompt: "p", max_steps: 10)
    )
    @parent_chat = Chat.create!(agent_name: "chief_of_staff")
    @child_chat  = Chat.create!(agent_name: "engineering_manager", parent_chat: @parent_chat)
    @tool = Daan::Core::ReportBack.new(chat: @child_chat)
  end

  test "posts a user message in the parent chat" do
    assert_difference -> { @parent_chat.messages.where(role: "user").count }, 1 do
      @tool.execute(message: "Here are my findings.")
    end
  end

  test "message content includes system prefix, agent display name, and the report" do
    @tool.execute(message: "Here are my findings.")
    msg = @parent_chat.messages.where(role: "user").last
    assert_equal "[SYSTEM] Engineering Manager reported back: Here are my findings.", msg.content
  end

  test "enqueues LlmJob for the parent chat" do
    assert_enqueued_with(job: LlmJob, args: [ @parent_chat ]) do
      @tool.execute(message: "Here are my findings.")
    end
  end

  test "returns confirmation string" do
    result = @tool.execute(message: "Here are my findings.")
    assert_includes result, "Chief of Staff"
  end

  test "creates a visible assistant message in the current chat when there is no parent" do
    orphan_chat = Chat.create!(agent_name: "engineering_manager")
    tool = Daan::Core::ReportBack.new(chat: orphan_chat)
    assert_difference -> { orphan_chat.messages.where(role: "assistant", visible: true).count }, 1 do
      tool.execute(message: "Here are my findings.")
    end
  end

  test "visible message includes agent display name and report content when there is no parent" do
    orphan_chat = Chat.create!(agent_name: "engineering_manager")
    tool = Daan::Core::ReportBack.new(chat: orphan_chat)
    tool.execute(message: "Here are my findings.")
    msg = orphan_chat.messages.where(role: "assistant", visible: true).last
    assert_includes msg.content, "Engineering Manager"
    assert_includes msg.content, "Here are my findings."
  end

  test "does not enqueue LlmJob when there is no parent" do
    orphan_chat = Chat.create!(agent_name: "engineering_manager")
    tool = Daan::Core::ReportBack.new(chat: orphan_chat)
    assert_no_enqueued_jobs(only: LlmJob) do
      tool.execute(message: "Here are my findings.")
    end
  end
end
