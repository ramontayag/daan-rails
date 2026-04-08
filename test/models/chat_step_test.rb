require "test_helper"

class ChatStepTest < ActiveSupport::TestCase
  setup do
    @agent = build_agent
    Daan::Core::AgentRegistry.register(@agent)
    @chat = Chat.create!(agent_name: @agent.name)
  end

  test "belongs to chat" do
    step = ChatStep.create!(chat: @chat, title: "Clone repo", position: 1)
    assert_equal @chat, step.chat
  end

  test "title is required" do
    step = ChatStep.new(chat: @chat, position: 1)
    assert_not step.valid?
    assert_includes step.errors[:title], "can't be blank"
  end

  test "position is required" do
    step = ChatStep.new(chat: @chat, title: "Clone repo")
    assert_not step.valid?
    assert_includes step.errors[:position], "can't be blank"
  end

  test "status defaults to pending" do
    step = ChatStep.create!(chat: @chat, title: "Clone repo", position: 1)
    assert_equal "pending", step.status
  end

  test "status must be valid" do
    step = ChatStep.new(chat: @chat, title: "Clone repo", position: 1, status: "bogus")
    assert_not step.valid?
    assert_includes step.errors[:status], "is not included in the list"
  end

  test "position is unique within chat" do
    ChatStep.create!(chat: @chat, title: "Step one", position: 1)
    duplicate = ChatStep.new(chat: @chat, title: "Step two", position: 1)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:position], "has already been taken"
  end

  test "chat has_many steps ordered by position" do
    step_b = ChatStep.create!(chat: @chat, title: "Second", position: 2)
    step_a = ChatStep.create!(chat: @chat, title: "First", position: 1)
    assert_equal [ step_a, step_b ], @chat.chat_steps.to_a
  end
end
