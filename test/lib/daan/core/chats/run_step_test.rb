# test/lib/daan/chats/run_step_test.rb
require "test_helper"
require "ostruct"

class Daan::Core::Chats::RunStepTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    Daan::Core::AgentRegistry.register(build_agent(name: "test_agent"))
    Daan::Core::AgentRegistry.register(build_agent(name: "parent_agent"))
    @chat = Chat.create!(agent_name: "test_agent")
    @chat.start!
  end

  test "returns the response from chat.step" do
    response = OpenStruct.new("tool_call?" => false, role: "assistant", tool_calls: nil)
    @chat.stub(:step, response) do
      result = Daan::Core::Chats::RunStep.call(@chat, context_user_message_id: nil)
      assert_equal response, result
    end
  end

  test "stamps context_user_message_id on the assistant message" do
    user_msg = @chat.messages.create!(role: "user", content: "hello")
    chat = @chat
    step_callable = ->(*) {
      chat.messages.create!(role: "assistant", content: "reply")
      OpenStruct.new("tool_call?" => false, role: "assistant", tool_calls: nil)
    }
    @chat.stub(:step, step_callable) do
      Daan::Core::Chats::RunStep.call(@chat, context_user_message_id: user_msg.id)
      assert_equal user_msg.id, @chat.messages.where(role: "assistant").last.context_user_message_id
    end
  end

  test "transitions chat to failed and re-raises on exception" do
    @chat.stub(:step, ->(*) { raise "LLM down" }) do
      assert_raises(RuntimeError) { Daan::Core::Chats::RunStep.call(@chat, context_user_message_id: nil) }
    end
    assert @chat.reload.failed?
  end

  test "notifies parent when chat fails and parent exists" do
    parent_chat = Chat.create!(agent_name: "parent_agent")
    @chat.update!(parent_chat: parent_chat)
    @chat.stub(:step, ->(*) { raise "LLM down" }) do
      assert_raises(RuntimeError) { Daan::Core::Chats::RunStep.call(@chat, context_user_message_id: nil) }
    end
    notification = parent_chat.messages.find_by("content LIKE ?", "%thread is now failed%")
    assert notification
  end
end
