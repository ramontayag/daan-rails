require "test_helper"

class Daan::Core::CreateMessageTest < ActiveSupport::TestCase
  include ActionCable::TestHelper
  include ActiveJob::TestHelper

  setup do
    @agent = build_agent
    Daan::Core::AgentRegistry.register(@agent)
    @chat = Chat.create!(agent_name: @agent.name)
  end

  test "creates message and broadcasts to chat stream" do
    assert_broadcasts("chat_#{@chat.id}", 1) do
      Daan::Core::CreateMessage.call(@chat, role: "user", content: "Hello")
    end
    assert_equal "Hello", Message.last.content
    assert_equal "user", Message.last.role
  end

  test "works for assistant role too" do
    assert_broadcasts("chat_#{@chat.id}", 1) do
      Daan::Core::CreateMessage.call(@chat, role: "assistant", content: "Hi there")
    end
  end

  test "returns the created message" do
    message = Daan::Core::CreateMessage.call(@chat, role: "user", content: "Hello")
    assert_instance_of Message, message
    assert_equal "Hello", message.content
  end

  test "enqueues LlmJob for user messages" do
    assert_enqueued_with(job: LlmJob) do
      Daan::Core::CreateMessage.call(@chat, role: "user", content: "Hello")
    end
  end

  test "does not enqueue LlmJob for assistant messages" do
    assert_no_enqueued_jobs(only: LlmJob) do
      Daan::Core::CreateMessage.call(@chat, role: "assistant", content: "Hi")
    end
  end
end
