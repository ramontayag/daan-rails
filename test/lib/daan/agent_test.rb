# test/lib/daan/agent_test.rb
require "test_helper"

class Daan::AgentTest < ActiveSupport::TestCase
  setup do
    @agent = Daan::Agent.new(
      name: "chief_of_staff",
      display_name: "Chief of Staff",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You are the Chief of Staff.",
      max_turns: 10
    )
  end

  test "has expected attributes" do
    assert_equal "chief_of_staff", @agent.name
    assert_equal "Chief of Staff", @agent.display_name
    assert_equal "claude-sonnet-4-20250514", @agent.model_name
    assert_equal 10, @agent.max_turns
  end

  test "to_param returns name for URL routing" do
    assert_equal "chief_of_staff", @agent.to_param
  end

  test "busy? is false when no in-progress chats" do
    assert_not @agent.busy?
  end

  test "busy? is true when agent has an in-progress chat" do
    Chat.create!(agent_name: "chief_of_staff").start!
    assert @agent.busy?
  end

  test "max_turns_reached? at the limit" do
    assert @agent.max_turns_reached?(10)
    assert_not @agent.max_turns_reached?(9)
  end

  test "tools defaults to empty array when not provided" do
    agent = Daan::Agent.new(
      name: "test", display_name: "Test", model_name: "m",
      system_prompt: "p", max_turns: 5
    )
    assert_equal [], agent.tools
  end

  test "tools stores the provided array" do
    agent = Daan::Agent.new(
      name: "test", display_name: "Test", model_name: "m",
      system_prompt: "p", max_turns: 5, tools: ["Foo"]
    )
    assert_equal ["Foo"], agent.tools
  end
end
