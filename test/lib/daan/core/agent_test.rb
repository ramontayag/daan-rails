# test/lib/daan/agent_test.rb
require "test_helper"

class Daan::Core::AgentTest < ActiveSupport::TestCase
  setup do
    @agent = Daan::Core::Agent.new(
      name: "chief_of_staff",
      display_name: "Chief of Staff",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You are the Chief of Staff.",
      max_steps: 10
    )
  end

  test "has expected attributes" do
    assert_equal "chief_of_staff", @agent.name
    assert_equal "Chief of Staff", @agent.display_name
    assert_equal "claude-sonnet-4-20250514", @agent.model_name
    assert_equal 10, @agent.max_steps
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

  test "max_steps_reached? at the limit" do
    assert @agent.max_steps_reached?(10)
    assert_not @agent.max_steps_reached?(9)
  end

  test "workspace defaults to nil when not provided" do
    agent = build_agent(name: "test")
    assert_nil agent.workspace
  end

  test "tools returns empty array when no base_tools" do
    agent = build_agent(name: "test")
    assert_equal [], agent.tools
  end

  test "tools returns workspace-bound instances" do
    workspace = Dir.mktmpdir
    tool_class = Class.new(RubyLLM::Tool) do
      description "test"
      def initialize(workspace: nil, chat: nil, storage: nil) = @workspace = workspace
      def execute = "ok"
    end
    agent = Daan::Core::Agent.new(
      name: "test",
      workspace: workspace, base_tools: [ tool_class ]
    )
    bound = agent.tools
    assert_equal 1, bound.length
    assert bound.first.is_a?(tool_class)
  ensure
    FileUtils.rm_rf(workspace)
  end

  test "delegates_to defaults to empty array" do
    agent = build_agent(name: "test")
    assert_equal [], agent.delegates_to
  end

  test "delegates_to is set from constructor" do
    agent = Daan::Core::Agent.new(
      name: "cos",
      delegates_to: [ "engineering_manager" ]
    )
    assert_equal [ "engineering_manager" ], agent.delegates_to
  end

  test "tools passes storage to tool initializer" do
    received_storage = nil
    spy_tool = Class.new(RubyLLM::Tool) do
      description "spy"
      define_method(:initialize) do |workspace: nil, chat: nil, storage: nil, **|
        received_storage = storage
      end
      define_method(:execute) { "ok" }
    end

    agent = Daan::Core::Agent.new(
      name: "test", base_tools: [ spy_tool ]
    )
    chat = Chat.create!(agent_name: "test")
    agent.tools(chat: chat)

    assert_same Daan::Core::Memory.storage, received_storage
  end
end
