# test/lib/daan/chats/run_step_test.rb
require "test_helper"
require "ostruct"

class Daan::Chats::RunStepTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    Daan::AgentRegistry.register(
      Daan::Agent.new(
        name: "test_agent", display_name: "Test Agent",
        model_name: "claude-sonnet-4-20250514",
        system_prompt: "You are a test agent.", max_steps: 3
      )
    )
    Daan::AgentRegistry.register(
      Daan::Agent.new(
        name: "parent_agent", display_name: "Parent Agent",
        model_name: "claude-sonnet-4-20250514",
        system_prompt: "Parent.", max_steps: 15
      )
    )
    @chat = Chat.create!(agent_name: "test_agent")
    @chat.start!
  end

  test "returns the response from chat.step" do
    response = OpenStruct.new("tool_call?" => false, role: "assistant", tool_calls: nil)
    @chat.define_singleton_method(:step) { |*| response }

    result = Daan::Chats::RunStep.call(@chat, context_user_message_id: nil)

    assert_equal response, result
  ensure
    @chat.singleton_class.remove_method(:step) if @chat.singleton_class.method_defined?(:step, false)
  end

  test "stamps context_user_message_id on the assistant message" do
    user_msg = @chat.messages.create!(role: "user", content: "hello")
    @chat.define_singleton_method(:step) do |*|
      messages.create!(role: "assistant", content: "reply")
      OpenStruct.new("tool_call?" => false, role: "assistant", tool_calls: nil)
    end

    Daan::Chats::RunStep.call(@chat, context_user_message_id: user_msg.id)

    assert_equal user_msg.id, @chat.messages.where(role: "assistant").last.context_user_message_id
  ensure
    @chat.singleton_class.remove_method(:step) if @chat.singleton_class.method_defined?(:step, false)
  end

  test "transitions chat to failed and re-raises on exception" do
    @chat.define_singleton_method(:step) { |*| raise "LLM down" }

    assert_raises(RuntimeError) { Daan::Chats::RunStep.call(@chat, context_user_message_id: nil) }
    assert @chat.reload.failed?
  ensure
    @chat.singleton_class.remove_method(:step) if @chat.singleton_class.method_defined?(:step, false)
  end

  test "notifies parent when chat fails and parent exists" do
    parent_chat = Chat.create!(agent_name: "parent_agent")
    @chat.update!(parent_chat: parent_chat)
    @chat.define_singleton_method(:step) { |*| raise "LLM down" }

    assert_raises(RuntimeError) { Daan::Chats::RunStep.call(@chat, context_user_message_id: nil) }

    notification = parent_chat.messages.find_by("content LIKE ?", "%thread is now failed%")
    assert notification
  ensure
    @chat.singleton_class.remove_method(:step) if @chat.singleton_class.method_defined?(:step, false)
  end
end
