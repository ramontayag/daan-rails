# test/lib/daan/chats/start_conversation_test.rb
require "test_helper"

class Daan::Core::Chats::StartConversationTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @agent = build_agent
    Daan::Core::AgentRegistry.register(@agent)
    @chat = Chat.create!(agent_name: @agent.name)
  end

  test "transitions a pending chat to in_progress" do
    Daan::Core::Chats::StartConversation.call(@chat)
    assert @chat.reload.in_progress?
  end

  test "resumes a completed chat" do
    @chat.start!
    @chat.finish!
    Daan::Core::Chats::StartConversation.call(@chat)
    assert @chat.reload.in_progress?
  end

  test "resumes a blocked chat" do
    @chat.start!
    @chat.block!
    Daan::Core::Chats::StartConversation.call(@chat)
    assert @chat.reload.in_progress?
  end

  test "resumes a failed chat" do
    @chat.fail!
    Daan::Core::Chats::StartConversation.call(@chat)
    assert @chat.reload.in_progress?
  end

  test "removes orphaned empty assistant messages before starting" do
    orphan = @chat.messages.create!(role: "assistant", content: "")
    Daan::Core::Chats::StartConversation.call(@chat)
    assert_not Message.exists?(orphan.id)
  end

  test "does not remove assistant messages that have content" do
    keeper = @chat.messages.create!(role: "assistant", content: "I did something")
    Daan::Core::Chats::StartConversation.call(@chat)
    assert Message.exists?(keeper.id)
  end
end
