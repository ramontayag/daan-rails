require "test_helper"

class AgentAllowedCommandsTest < ActiveSupport::TestCase
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
      system_prompt: "You help.", max_steps: 5,
      base_tools: [ narrow_tool ]
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
      system_prompt: "You help.", max_steps: 5,
      base_tools: [ fake_tool ]
    )
    instance = agent.tools(chat: nil).first
    assert instance.singleton_class.ancestors.include?(Daan::Core::SafeExecute)
  end

  test "Bash uses universal ALLOWED_COMMANDS by default" do
    workspace = Daan::Workspace.new(Dir.mktmpdir)
    tool = Daan::Core::Bash.new(workspace: workspace)
    result = tool.execute(commands: [ [ "pwd" ] ])
    assert_includes result, workspace.root.to_s
  ensure
    FileUtils.rm_rf(workspace.root.to_s)
  end

  test "effective_allowed_commands returns global list when agent has no allowed_commands" do
    agent = Daan::Agent.new(
      name: "test", display_name: "Test",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You help.", max_steps: 5
    )
    assert_equal Daan::Core::Bash::ALLOWED_COMMANDS, agent.effective_allowed_commands
  end

  test "effective_allowed_commands returns agent list when set" do
    agent = Daan::Agent.new(
      name: "test", display_name: "Test",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You help.", max_steps: 5,
      allowed_commands: %w[git gh]
    )
    assert_equal %w[git gh], agent.effective_allowed_commands
  end

  test "raises at construction when agent declares command not in global list" do
    error = assert_raises(ArgumentError) do
      Daan::Agent.new(
        name: "test", display_name: "Test",
        model_name: "claude-sonnet-4-20250514",
        system_prompt: "You help.", max_steps: 5,
        allowed_commands: %w[git nuclear_launch]
      )
    end
    assert_includes error.message, "nuclear_launch"
  end

  test "tools passes effective_allowed_commands to Bash" do
    workspace = Daan::Workspace.new(Dir.mktmpdir)
    agent = Daan::Agent.new(
      name: "test", display_name: "Test",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You help.", max_steps: 5,
      base_tools: [ Daan::Core::Bash ],
      workspace: workspace,
      allowed_commands: %w[echo pwd]
    )

    bash_instance = agent.tools(chat: nil).first
    # echo is in the agent's allowed list — should work
    result = bash_instance.execute(commands: [ [ "echo", "hi" ] ])
    assert_includes result, "hi"

    # git is NOT in the agent's allowed list — SafeExecute (already prepended
    # by Agent#tools) catches the error and returns it as a string
    result = bash_instance.execute(commands: [ [ "git", "status" ] ])
    assert_match(/not allowed/, result)
  ensure
    FileUtils.rm_rf(workspace&.root.to_s)
  end
end
