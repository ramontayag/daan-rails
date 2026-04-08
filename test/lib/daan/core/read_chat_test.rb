require "test_helper"

class Daan::Core::ReadChatTest < ActiveSupport::TestCase
  setup do
    Daan::Core::AgentRegistry.register(build_agent(name: "developer"))

    @chat = Chat.create!(agent_name: "developer")
    @chat.messages.create!(role: "user", content: "Please implement authentication")
    @chat.messages.create!(role: "assistant", content: "I will implement authentication using JWT")
    @chat.messages.create!(role: "tool", content: "tool call result")

    @tool = Daan::Core::ReadChat.new
  end

  test "reads messages from a chat with default limit" do
    result = @tool.execute(chat_id: @chat.id)

    assert_includes result, "Please implement authentication"
    assert_includes result, "I will implement authentication using JWT"
  end

  test "only shows user and assistant messages, not tool messages" do
    result = @tool.execute(chat_id: @chat.id)

    assert_includes result, "[user]"
    assert_includes result, "[assistant]"
    refute_includes result, "tool call result"
  end

  test "includes chat metadata in header" do
    result = @tool.execute(chat_id: @chat.id)

    assert_includes result, "Chat ##{@chat.id}"
    assert_includes result, "developer"
    assert_includes result, "pending"
  end

  test "shows total message count and current window position" do
    result = @tool.execute(chat_id: @chat.id)

    assert_includes result, "2 messages"
    assert_includes result, "showing 1-2"
  end

  test "respects offset parameter" do
    result = @tool.execute(chat_id: @chat.id, offset: 1)

    refute_includes result, "Please implement authentication"
    assert_includes result, "I will implement authentication using JWT"
  end

  test "respects limit parameter" do
    result = @tool.execute(chat_id: @chat.id, limit: 1)

    assert_includes result, "Please implement authentication"
    refute_includes result, "I will implement authentication using JWT"
  end

  test "window position reflects offset in header" do
    result = @tool.execute(chat_id: @chat.id, offset: 1)

    assert_includes result, "showing 2-2"
  end

  test "returns error for nonexistent chat" do
    result = @tool.execute(chat_id: 999999)

    assert_includes result, "Error"
    assert_includes result, "999999"
    assert_includes result, "not found"
  end

  test "default limit is 20" do
    25.times { |i| @chat.messages.create!(role: "user", content: "message #{i}") }

    result = @tool.execute(chat_id: @chat.id)

    assert_includes result, "showing 1-20"
  end

  test "max limit is capped at 50" do
    55.times { |i| @chat.messages.create!(role: "user", content: "bulk message #{i}") }

    result = @tool.execute(chat_id: @chat.id, limit: 100)

    assert_includes result, "showing 1-50"
  end
end
