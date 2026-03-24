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
    calls = []

    @chat.define_singleton_method(:with_model) { |m| calls << [ :with_model, m ]; self }
    @chat.define_singleton_method(:with_instructions) { |p| calls << [ :with_instructions, p ]; self }
    @chat.define_singleton_method(:with_tools) { |*t| calls << [ :with_tools, t ]; self }

    Daan::Chats::ConfigureLlm.call(@chat, @agent)

    assert_equal :with_model, calls[0][0]
    assert_equal "claude-sonnet-4-20250514", calls[0][1]
    assert_equal :with_instructions, calls[1][0]
    assert_includes calls[1][1], "You are a test agent."
    assert_equal :with_tools, calls[2][0]
  ensure
    %i[with_model with_instructions with_tools].each do |m|
      @chat.singleton_class.remove_method(m) if @chat.singleton_class.method_defined?(m, false)
    end
  end
end
