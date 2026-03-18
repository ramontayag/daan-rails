require "test_helper"

class Daan::ConversationRunnerStepInjectionTest < ActiveSupport::TestCase
  setup do
    Daan::AgentRegistry.register(
      Daan::Agent.new(
        name: "developer", display_name: "Developer",
        model_name: "claude-sonnet-4-20250514",
        system_prompt: "You are a developer.", max_turns: 10
      )
    )
    @chat = Chat.create!(agent_name: "developer")
  end

  test "appends steps to system prompt when steps exist" do
    ChatStep.create!(chat: @chat, title: "Clone repo", position: 1, status: "completed")
    ChatStep.create!(chat: @chat, title: "Write tests", position: 2, status: "in_progress")
    ChatStep.create!(chat: @chat, title: "Implement", position: 3)

    with_stub_memories([]) do
      prompt = Daan::ConversationRunner.build_system_prompt(@chat, @chat.agent)

      assert_includes prompt, "You are a developer."
      assert_includes prompt, "## Your Current Steps"
      assert_includes prompt, "1. [x] Clone repo"
      assert_includes prompt, "2. [in progress] Write tests"
      assert_includes prompt, "3. [ ] Implement"
    end
  end

  test "does not append steps section when no steps exist" do
    with_stub_memories([]) do
      prompt = Daan::ConversationRunner.build_system_prompt(@chat, @chat.agent)

      assert_includes prompt, "You are a developer."
      assert_not_includes prompt, "Your Current Steps"
    end
  end

  private

  def with_stub_memories(results, &block)
    sc = Daan::ConversationRunner.singleton_class
    sc.alias_method(:__orig_retrieve_memories__, :retrieve_memories)
    sc.define_method(:retrieve_memories) { |_chat| results }
    block.call
  ensure
    sc.alias_method(:retrieve_memories, :__orig_retrieve_memories__)
    sc.remove_method(:__orig_retrieve_memories__)
  end
end
