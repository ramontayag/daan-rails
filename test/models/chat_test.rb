# test/models/chat_test.rb
require "test_helper"

class ChatTest < ActiveSupport::TestCase
  setup do
    @agent = Daan::Agent.new(name: "chief_of_staff", display_name: "CoS",
                             model_name: "claude-sonnet-4-20250514",
                             system_prompt: "You are CoS.", max_turns: 10)
    Daan::AgentRegistry.register(@agent)
  end

  test "agent returns the registered Daan::Agent" do
    chat = Chat.new(agent_name: "chief_of_staff")
    assert_equal @agent, chat.agent
  end

  test "defaults to pending state" do
    assert Chat.new.pending?
  end

  test "start! transitions pending to in_progress" do
    chat = chats(:hello_cos)
    chat.start!
    assert chat.in_progress?
  end

  test "finish! transitions in_progress to completed" do
    chat = chats(:hello_cos)
    chat.start!
    chat.finish!
    assert chat.completed?
  end

  test "invalid transition raises AASM::InvalidTransition" do
    chat = chats(:hello_cos)
    assert_raises(AASM::InvalidTransition) { chat.finish! }
  end

  test "turn_count defaults to 0" do
    assert_equal 0, Chat.new.turn_count
  end


  test "raises AgentNotFoundError for unknown agent_name" do
    chat = Chat.new(agent_name: "ghost")
    assert_raises(Daan::AgentNotFoundError) { chat.agent }
  end

  test "parent_chat is optional" do
    chat = Chat.create!(agent_name: "chief_of_staff")
    assert_nil chat.parent_chat
  end

  test "sub_chats association returns child chats" do
    parent = Chat.create!(agent_name: "chief_of_staff")
    child  = Chat.create!(agent_name: "chief_of_staff", parent_chat: parent)
    assert_includes parent.sub_chats, child
  end

  test "parent_chat association returns parent" do
    parent = Chat.create!(agent_name: "chief_of_staff")
    child  = Chat.create!(agent_name: "chief_of_staff", parent_chat: parent)
    assert_equal parent, child.parent_chat
  end
end
