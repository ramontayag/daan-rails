require "test_helper"
require "ostruct"

class ChatBroadcastTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    Daan::Core::AgentRegistry.clear
    @agent = build_agent
    Daan::Core::AgentRegistry.register(@agent)
    @chat = Chat.create!(agent_name: @agent.name)
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
    parent = Chat.create!(agent_name: @agent.name)
    child  = Chat.create!(agent_name: @agent.name, parent_chat: parent)

    # parent has sub_chats, so 2 targeted broadcasts (totals + rows) are sent
    assert_broadcasts("chat_#{parent.id}", 2) do
      child.broadcast_chat_cost
    end
  end

  test "ConversationRunner broadcasts after start! and after finish!" do
    step_response = OpenStruct.new("tool_call?" => false, role: "assistant", tool_calls: nil)
    @chat.stub(:with_model, @chat) do
      @chat.stub(:with_instructions, @chat) do
        @chat.stub(:step, step_response) do
          assert_broadcasts("agents", 2) do
            Daan::Core::ConversationRunner.call(@chat)
          end
        end
      end
    end
  end

  test "ConversationRunner broadcasts after start! and after fail! when step raises" do
    @chat.stub(:with_model, @chat) do
      @chat.stub(:with_instructions, @chat) do
        @chat.stub(:step, ->(*) { raise "LLM error" }) do
          assert_broadcasts("agents", 2) do
            assert_raises(RuntimeError) { Daan::Core::ConversationRunner.call(@chat) }
          end
        end
      end
    end
  end
end
