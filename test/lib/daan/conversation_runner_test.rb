# test/lib/daan/conversation_runner_test.rb
require "test_helper"

class Daan::ConversationRunnerTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @agent = Daan::Agent.new(
      name: "test_agent", display_name: "Test Agent",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You are a test agent.",
      max_turns: 3
    )
    Daan::AgentRegistry.register(@agent)
    @chat = Chat.create!(agent_name: "test_agent")
    @chat.messages.create!(role: "user", content: "Hello agent")
  end

  test "transitions to completed" do
    with_stub_complete { Daan::ConversationRunner.call(@chat) }
    assert @chat.reload.completed?
  end

  test "increments turn_count" do
    with_stub_complete { Daan::ConversationRunner.call(@chat) }
    assert_equal 1, @chat.reload.turn_count
  end

  test "transitions to blocked when max_turns reached" do
    @chat.update!(turn_count: @agent.max_turns - 1)
    with_stub_complete { Daan::ConversationRunner.call(@chat) }
    assert @chat.reload.blocked?
  end

  test "transitions to failed and reraises on exception" do
    with_stub_complete(raise_error: RuntimeError.new("LLM down")) do
      assert_raises(RuntimeError) { Daan::ConversationRunner.call(@chat) }
    end
    assert @chat.reload.failed?
  end

  test "broadcasts assistant message to chat stream after complete" do
    @chat.messages.create!(role: "assistant", content: "Hello human")
    with_stub_complete do
      assert_broadcasts("chat_#{@chat.id}", 1) do
        Daan::ConversationRunner.call(@chat)
      end
    end
  end

  private

  def with_stub_complete(raise_error: nil, &block)
    called = false
    @chat.define_singleton_method(:complete) do |*|
      called = true
      raise raise_error if raise_error
    end
    block.call
    assert called, "expected complete to be called" unless raise_error
  ensure
    @chat.singleton_class.remove_method(:complete)
  end
end
