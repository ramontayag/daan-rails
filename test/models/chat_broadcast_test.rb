require "test_helper"
require "ostruct"

class ChatBroadcastTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    Daan::AgentRegistry.clear
    Daan::AgentRegistry.register(Daan::Agent.new(
      name: "chief_of_staff", display_name: "CoS",
      model_name: "claude-3-5-haiku-20241022", system_prompt: "p", max_steps: 10
    ))
    @chat = Chat.create!(agent_name: "chief_of_staff")
  end

  test "broadcast_agent_status broadcasts AgentItemComponent to agents stream" do
    assert_broadcasts("agents", 1) do
      @chat.broadcast_agent_status
    end
  end

  test "broadcast_chat_cost broadcasts to own chat stream" do
    assert_broadcasts("chat_#{@chat.id}", 1) do
      @chat.broadcast_chat_cost
    end
  end

  test "broadcast_chat_cost also broadcasts to parent chat stream" do
    parent = Chat.create!(agent_name: "chief_of_staff")
    child  = Chat.create!(agent_name: "chief_of_staff", parent_chat: parent)

    # parent has sub_chats, so 2 targeted broadcasts (totals + rows) are sent
    assert_broadcasts("chat_#{parent.id}", 2) do
      child.broadcast_chat_cost
    end
  end

  test "ConversationRunner broadcasts after start! and after finish!" do
    assert_broadcasts("agents", 2) do
      @chat.define_singleton_method(:with_model) { |_| self }
      @chat.define_singleton_method(:with_instructions) { |_| self }
      step_response = OpenStruct.new("tool_call?" => false, role: "assistant", tool_calls: nil)
      @chat.define_singleton_method(:step) { step_response }
      Daan::ConversationRunner.call(@chat)
    end
  end

  test "ConversationRunner broadcasts after start! and after fail! when step raises" do
    assert_broadcasts("agents", 2) do
      @chat.define_singleton_method(:with_model) { |_| self }
      @chat.define_singleton_method(:with_instructions) { |_| self }
      @chat.define_singleton_method(:step) { raise "LLM error" }
      assert_raises(RuntimeError) { Daan::ConversationRunner.call(@chat) }
    end
  end
end
