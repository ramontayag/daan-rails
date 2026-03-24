# test/lib/daan/chats/configure_llm_test.rb
require "test_helper"

class Daan::Chats::ConfigureLlmTest < ActiveSupport::TestCase
  setup do
    Daan::AgentRegistry.register(
      Daan::Agent.new(
        name: "test_agent", display_name: "Test Agent",
        model_name: "claude-sonnet-4-20250514",
        system_prompt: "You are a test agent.", max_steps: 3
      )
    )
    @chat = Chat.create!(agent_name: "test_agent")
    @agent = @chat.agent
  end

  test "calls with_model, with_instructions, and with_tools on the chat" do
    model_arg = nil
    instructions_arg = nil
    tools_called = false

    @chat.stub(:with_model, ->(m) { model_arg = m; @chat }) do
      @chat.stub(:with_instructions, ->(p) { instructions_arg = p; @chat }) do
        @chat.stub(:with_tools, ->(*) { tools_called = true; @chat }) do
          Daan::Chats::ConfigureLlm.call(@chat, @agent)
        end
      end
    end

    assert_equal "claude-sonnet-4-20250514", model_arg
    assert_includes instructions_arg, "You are a test agent."
    assert tools_called
  end
end
