require "test_helper"

class AgentAllowedCommandsTest < ActiveSupport::TestCase
  test "tools without allowed_commands in initializer are instantiated without error" do
    received_kwargs = nil
    narrow_tool = Class.new do
      define_method(:initialize) do |workspace: nil, chat: nil|
        received_kwargs = { workspace: workspace, chat: chat }
      end
    end

    agent = Daan::Core::Agent.new(
      name: "test",
      base_tools: [ narrow_tool ]
    )
    agent.tools(chat: nil)
    assert_equal({ workspace: nil, chat: nil }, received_kwargs)
  end

  test "agent tools has SafeExecute prepended on every instance" do
    fake_tool = Class.new(RubyLLM::Tool) do
      def execute; end
    end

    agent = Daan::Core::Agent.new(
      name: "test",
      base_tools: [ fake_tool ]
    )
    instance = agent.tools(chat: nil).first
    assert instance.singleton_class.ancestors.include?(Daan::Core::SafeExecute)
  end

  test "Bash uses configured allowed_commands by default" do
    Daan::Core.configure { |c| c.allowed_commands = %w[pwd] }
    workspace = Daan::Core::Workspace.new(Dir.mktmpdir)
    tool = Daan::Core::Bash.new(workspace: workspace)
    result = tool.execute(commands: [ [ "pwd" ] ])
    assert_includes result, workspace.root.to_s
  ensure
    FileUtils.rm_rf(workspace.root.to_s)
  end

  test "effective_allowed_commands returns configured list when agent has no allowed_commands" do
    Daan::Core.configure { |c| c.allowed_commands = %w[git gh ls] }
    agent = build_agent(name: "test")
    assert_equal %w[git gh ls], agent.effective_allowed_commands
  end

  test "effective_allowed_commands returns agent list when set" do
    Daan::Core.configure { |c| c.allowed_commands = %w[git gh ls] }
    agent = Daan::Core::Agent.new(
      name: "test",
      allowed_commands: %w[git gh]
    )
    assert_equal %w[git gh], agent.effective_allowed_commands
  end

  test "raises at construction when agent declares command not in configured list" do
    Daan::Core.configure { |c| c.allowed_commands = %w[git gh] }
    error = assert_raises(ArgumentError) do
      Daan::Core::Agent.new(
        name: "test",
        allowed_commands: %w[git nuclear_launch]
      )
    end
    assert_includes error.message, "nuclear_launch"
  end

  test "tools passes effective_allowed_commands to Bash" do
    Daan::Core.configure { |c| c.allowed_commands = %w[echo pwd git] }
    workspace = Daan::Core::Workspace.new(Dir.mktmpdir)
    agent = Daan::Core::Agent.new(
      name: "test",
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
