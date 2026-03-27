# test/lib/daan/chats/inject_datetime_test.rb
require "test_helper"

class Daan::Chats::InjectDatetimeTest < ActiveSupport::TestCase
  setup do
    @agent = Daan::Agent.new(
      name: "test_agent", display_name: "Test Agent",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You are a test agent.",
      max_steps: 3
    )
    Daan::AgentRegistry.register(@agent)
    @chat = Chat.create!(agent_name: "test_agent")
  end

  test "creates a user message with visible: false" do
    Daan::Chats::InjectDatetime.call(@chat)

    msg = @chat.messages.order(:id).last
    assert_equal "user", msg.role
    assert_equal false, msg.visible
  end

  test "message content includes the day of week" do
    travel_to Time.new(2026, 3, 27, 14, 30, 0, "+00:00") do
      Daan::Chats::InjectDatetime.call(@chat)
    end

    msg = @chat.messages.order(:id).last
    assert_includes msg.content, "Friday"
  end

  test "message content includes the full date" do
    travel_to Time.new(2026, 3, 27, 14, 30, 0, "+00:00") do
      Daan::Chats::InjectDatetime.call(@chat)
    end

    msg = @chat.messages.order(:id).last
    assert_includes msg.content, "March 27, 2026"
  end

  test "message content includes the time" do
    travel_to Time.new(2026, 3, 27, 14, 30, 0, "+00:00") do
      Daan::Chats::InjectDatetime.call(@chat)
    end

    msg = @chat.messages.order(:id).last
    assert_includes msg.content, "14:30"
  end

  test "message content includes UTC offset" do
    travel_to Time.new(2026, 3, 27, 14, 30, 0, "+00:00") do
      Daan::Chats::InjectDatetime.call(@chat)
    end

    msg = @chat.messages.order(:id).last
    assert_includes msg.content, "+00:00"
  end

  test "does not inject a second message when called again on the same chat" do
    Daan::Chats::InjectDatetime.call(@chat)
    Daan::Chats::InjectDatetime.call(@chat)

    datetime_messages = @chat.messages.where(
      role: "user",
      visible: false
    ).select { |m| m.content.include?("[System] Current datetime:") }

    assert_equal 1, datetime_messages.size
  end

  test "injects on a chat that already has visible user messages" do
    @chat.messages.create!(role: "user", content: "Hello agent", visible: true)

    assert_difference -> { @chat.messages.where(visible: false).count }, 1 do
      Daan::Chats::InjectDatetime.call(@chat)
    end
  end
end
