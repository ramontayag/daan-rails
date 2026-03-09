require "test_helper"

class ChatBroadcastTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    Daan::AgentRegistry.clear
    Daan::AgentRegistry.register(Daan::Agent.new(
      name: "chief_of_staff", display_name: "CoS",
      model_name: "claude-3-5-haiku-20241022", system_prompt: "p", max_turns: 10
    ))
    @chat = Chat.create!(agent_name: "chief_of_staff")
  end

  test "broadcast_agent_status broadcasts AgentItemComponent to agents stream" do
    assert_broadcasts("agents", 1) do
      @chat.broadcast_agent_status
    end
  end

  test "ConversationRunner broadcasts after start! and after finish!" do
    assert_broadcasts("agents", 2) do
      @chat.define_singleton_method(:with_model) { |_| self }
      @chat.define_singleton_method(:with_instructions) { |_| self }
      @chat.define_singleton_method(:complete) { self }
      Daan::ConversationRunner.call(@chat)
    end
  end

  test "ConversationRunner broadcasts after start! and after fail! when complete raises" do
    assert_broadcasts("agents", 2) do
      @chat.define_singleton_method(:with_model) { |_| self }
      @chat.define_singleton_method(:with_instructions) { |_| self }
      @chat.define_singleton_method(:complete) { raise "LLM error" }
      assert_raises(RuntimeError) { Daan::ConversationRunner.call(@chat) }
    end
  end
end
