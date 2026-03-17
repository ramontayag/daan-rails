require "test_helper"

class Daan::Core::CreateStepsTest < ActiveSupport::TestCase
  setup do
    Daan::AgentRegistry.register(
      Daan::Agent.new(
        name: "developer", display_name: "Developer",
        model_name: "claude-sonnet-4-20250514",
        system_prompt: "You code.", max_turns: 10
      )
    )
    @chat = Chat.create!(agent_name: "developer")
  end

  test "creates steps with sequential positions" do
    tool = Daan::Core::CreateSteps.new(chat: @chat)
    result = tool.execute(steps: ["Clone repo", "Write tests", "Implement"])

    assert_equal 3, @chat.chat_steps.count
    steps = @chat.chat_steps.to_a
    assert_equal "Clone repo", steps[0].title
    assert_equal 1, steps[0].position
    assert_equal "pending", steps[0].status
    assert_equal "Write tests", steps[1].title
    assert_equal 2, steps[1].position
    assert_equal "Implement", steps[2].title
    assert_equal 3, steps[2].position
    assert_includes result, "1. [ ] Clone repo"
    assert_includes result, "2. [ ] Write tests"
    assert_includes result, "3. [ ] Implement"
  end

  test "appends to existing steps" do
    ChatStep.create!(chat: @chat, title: "Existing step", position: 1)
    tool = Daan::Core::CreateSteps.new(chat: @chat)
    tool.execute(steps: ["New step"])

    assert_equal 2, @chat.chat_steps.count
    assert_equal 2, @chat.chat_steps.last.position
  end

  test "returns error for empty list" do
    tool = Daan::Core::CreateSteps.new(chat: @chat)
    result = tool.execute(steps: [])

    assert_includes result, "at least one"
    assert_equal 0, @chat.chat_steps.count
  end
end
