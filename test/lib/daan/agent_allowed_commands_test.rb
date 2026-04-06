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
end
