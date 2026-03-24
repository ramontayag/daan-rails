# test/lib/daan/chats/finish_or_reenqueue_test.rb
require "test_helper"
require "ostruct"

class Daan::Chats::FinishOrReenqueueTest < ActiveSupport::TestCase
  include ActionCable::TestHelper
  include ActiveJob::TestHelper

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
    @chat.messages.create!(role: "user", content: "Do the thing")
    @chat.start!
    @agent = @chat.agent
  end

  # -- final response (no tool call) --

  test "finishes the chat when response has no tool calls" do
    response = OpenStruct.new("tool_call?" => false)
    Daan::Chats::FinishOrReenqueue.call(@chat, @agent, response)
    assert @chat.reload.completed?
  end

  test "re-enqueues LlmJob when response has tool calls and limit not reached" do
    response = OpenStruct.new("tool_call?" => true)
    assert_enqueued_with(job: LlmJob, args: [ @chat ]) do
      Daan::Chats::FinishOrReenqueue.call(@chat, @agent, response)
    end
  end

  # -- max steps --

  test "blocks the chat when max steps reached" do
    # Simulate RunStep having just created the final assistant message
    @agent.max_steps.times { @chat.messages.create!(role: "assistant", content: "step") }
    response = OpenStruct.new("tool_call?" => true)
    Daan::Chats::FinishOrReenqueue.call(@chat, @agent, response)
    assert @chat.reload.blocked?
  end

  test "notifies parent when max steps reached and parent exists" do
    parent_chat = Chat.create!(agent_name: "parent_agent")
    @chat.update!(parent_chat: parent_chat)
    @agent.max_steps.times { @chat.messages.create!(role: "assistant", content: "step") }

    response = OpenStruct.new("tool_call?" => true)
    Daan::Chats::FinishOrReenqueue.call(@chat, @agent, response)

    notification = parent_chat.messages.find_by("content LIKE ?", "%thread is now blocked%")
    assert notification
  end

  # -- approaching step limit warning --

  test "injects warning when 3 steps remain and parent exists" do
    parent_chat = Chat.create!(agent_name: "parent_agent")
    @chat.update!(parent_chat: parent_chat)
    @agent.max_steps = 10
    7.times { @chat.messages.create!(role: "assistant", content: "step") }
    # step_count = 7, remaining = 3 → triggers warning

    response = OpenStruct.new("tool_call?" => true)
    Daan::Chats::FinishOrReenqueue.call(@chat, @agent, response)

    warning = @chat.messages.find_by("content LIKE ?", "%2 steps of work remaining%")
    assert warning
    assert_equal false, warning.visible
  end

  test "does not inject warning for top-level chat with no parent" do
    @agent.max_steps = 10
    7.times { @chat.messages.create!(role: "assistant", content: "step") }

    response = OpenStruct.new("tool_call?" => true)
    Daan::Chats::FinishOrReenqueue.call(@chat, @agent, response)

    assert_nil @chat.messages.find_by("content LIKE ?", "%2 steps of work remaining%")
  end
end
