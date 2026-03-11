require "test_helper"

class AgentAllowedCommandsTest < ActiveSupport::TestCase
  test "agent defaults allowed_commands to empty array" do
    agent = Daan::Agent.new(name: "test", display_name: "Test",
                             model_name: "claude-sonnet-4-20250514",
                             system_prompt: "You help.", max_turns: 5)
    assert_equal [], agent.allowed_commands
  end

  test "agent loader parses allowed_commands from frontmatter" do
    file = Tempfile.new(["agent", ".md"])
    file.write(<<~MD)
      ---
      name: tester
      display_name: Tester
      model: claude-sonnet-4-20250514
      max_turns: 5
      allowed_commands:
        - git
        - gh
      tools: []
      delegates_to: []
      ---
      You help.
    MD
    file.flush

    definition = Daan::AgentLoader.parse(file.path)
    assert_equal %w[git gh], definition[:allowed_commands]
  ensure
    file.close
    file.unlink
  end

  test "agent loader defaults allowed_commands to empty array when absent from frontmatter" do
    file = Tempfile.new(["agent", ".md"])
    file.write(<<~MD)
      ---
      name: tester
      display_name: Tester
      model: claude-sonnet-4-20250514
      max_turns: 5
      tools: []
      delegates_to: []
      ---
      You help.
    MD
    file.flush

    definition = Daan::AgentLoader.parse(file.path)
    assert_equal [], definition[:allowed_commands]
  ensure
    file.close
    file.unlink
  end

  test "tools without allowed_commands in initializer are instantiated without error" do
    received_kwargs = nil
    narrow_tool = Class.new do
      define_method(:initialize) do |workspace: nil, chat: nil|
        received_kwargs = { workspace: workspace, chat: chat }
      end
    end

    agent = Daan::Agent.new(
      name: "test", display_name: "Test",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You help.", max_turns: 5,
      base_tools: [narrow_tool],
      allowed_commands: %w[git gh]
    )
    agent.tools(chat: nil)
    assert_equal({ workspace: nil, chat: nil }, received_kwargs)
  end

  test "agent tools has SafeExecute prepended on every instance" do
    fake_tool = Class.new(RubyLLM::Tool) do
      def execute; end
    end

    agent = Daan::Agent.new(
      name: "test", display_name: "Test",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You help.", max_turns: 5,
      base_tools: [fake_tool]
    )
    instance = agent.tools(chat: nil).first
    assert instance.singleton_class.ancestors.include?(Daan::Core::SafeExecute)
  end

  test "agent tools receives allowed_commands at instantiation" do
    received = nil
    fake_tool = Class.new do
      define_method(:initialize) do |workspace: nil, chat: nil, allowed_commands: [], **|
        received = allowed_commands
      end
    end

    agent = Daan::Agent.new(
      name: "test", display_name: "Test",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You help.", max_turns: 5,
      base_tools: [fake_tool],
      allowed_commands: %w[git gh]
    )
    agent.tools(chat: nil)
    assert_equal %w[git gh], received
  end
end
