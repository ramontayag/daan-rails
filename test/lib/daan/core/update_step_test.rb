require "test_helper"

class Daan::Core::UpdateStepTest < ActiveSupport::TestCase
  setup do
    @agent = build_agent
    Daan::Core::AgentRegistry.register(@agent)
    @chat = Chat.create!(agent_name: @agent.name)
    @step = ChatStep.create!(chat: @chat, title: "Clone repo", position: 1)
  end

  test "updates step status to in_progress" do
    tool = Daan::Core::UpdateStep.new(chat: @chat)
    result = tool.execute(position: 1, status: "in_progress")

    assert_equal "in_progress", @step.reload.status
    assert_includes result, "in_progress"
  end

  test "updates step status to completed" do
    tool = Daan::Core::UpdateStep.new(chat: @chat)
    tool.execute(position: 1, status: "completed")

    assert_equal "completed", @step.reload.status
  end

  test "returns error for invalid position" do
    tool = Daan::Core::UpdateStep.new(chat: @chat)
    result = tool.execute(position: 99, status: "completed")

    assert_includes result, "No step"
  end

  test "returns error for invalid status" do
    tool = Daan::Core::UpdateStep.new(chat: @chat)
    result = tool.execute(position: 1, status: "bogus")

    assert_includes result, "Invalid status"
  end
end
