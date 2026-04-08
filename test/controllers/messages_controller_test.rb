# test/controllers/messages_controller_test.rb
require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    Chat.destroy_all
    Daan::Core::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
  end

  test "POST adds reply to existing thread" do
    chat = Chat.create!(agent_name: "chief_of_staff")
    chat.start!
    chat.finish!
    assert_no_difference "Chat.count" do
      post chat_thread_messages_path(chat),
           params: { message: { content: "Follow-up" } }
    end
  end

  test "POST saves message content" do
    chat = Chat.create!(agent_name: "chief_of_staff")
    chat.start!
    chat.finish!
    post chat_thread_messages_path(chat), params: { message: { content: "Follow-up" } }
    assert_equal "Follow-up", chat.messages.where(role: "user").last.content
  end

  test "POST enqueues LlmJob" do
    chat = Chat.create!(agent_name: "chief_of_staff")
    chat.start!
    chat.finish!
    assert_enqueued_with(job: LlmJob) do
      post chat_thread_messages_path(chat),
           params: { message: { content: "Reply" } }
    end
  end
end
