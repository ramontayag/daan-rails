require "test_helper"
require "ostruct"

class Daan::Core::Chats::RunStepWithHooksTest < ActiveSupport::TestCase
  setup do
    Daan::Core::AgentRegistry.register(build_agent(name: "test_agent"))
    @chat = Chat.create!(agent_name: "test_agent")
    @chat.messages.create!(role: "user", content: "Hello")
    @chat.start!
  end

  teardown { Daan::Core::Hook::Registry.clear }

  test "returns response and hooks array" do
    response, hooks = with_stub_step { run_step_with_hooks }

    assert_respond_to response, :tool_call?
    assert_kind_of Array, hooks
  end

  test "calls before_llm_call on hooks" do
    received_args = nil
    spy = build_hook(before_llm_call: ->(chat:, last_tool_calls:) {
      received_args = { chat: chat, last_tool_calls: last_tool_calls }
    })

    with_hooks(agent: [ spy ]) do
      with_stub_step { run_step_with_hooks }
    end

    assert_equal @chat, received_args[:chat]
    assert_respond_to received_args[:last_tool_calls], :each
  end

  test "calls before_conversation when step_count is 0" do
    received = nil
    spy = build_hook(before_conversation: ->(chat:) { received = chat })

    with_hooks(agent: [ spy ]) do
      with_stub_step { run_step_with_hooks }
    end

    assert_equal @chat, received
  end

  test "skips before_conversation when step_count > 0" do
    @chat.messages.create!(role: "assistant", content: "prior step")
    called = false
    spy = build_hook(before_conversation: ->(chat:) { called = true })

    with_hooks(agent: [ spy ]) do
      with_stub_step { run_step_with_hooks }
    end

    assert_not called
  end

  test "sets thread-local during RunStep and clears after" do
    captured = nil
    Daan::Core::Chats::ConfigureLlm.stub(:call, nil) do
      Daan::Core::Chats::RunStep.stub(:call, ->(_chat, **) {
        captured = Thread.current[:daan_active_hooks]
        OpenStruct.new("tool_call?" => false, role: "assistant")
      }) do
        run_step_with_hooks
      end
    end

    assert_not_nil captured
    assert_equal @chat, captured[:chat]
    assert_nil Thread.current[:daan_active_hooks]
  end

  test "clears thread-local and dispatches after_conversation(:failed) on exception" do
    received_status = nil
    spy = build_hook(after_conversation: ->(chat:, status:) { received_status = status })

    with_hooks(agent: [ spy ]) do
      Daan::Core::Chats::ConfigureLlm.stub(:call, nil) do
        @chat.stub(:step, ->(*) { raise "boom" }) do
          assert_raises(RuntimeError) { run_step_with_hooks }
        end
      end
    end

    assert_equal :failed, received_status
    assert_nil Thread.current[:daan_active_hooks]
  end

  test "hook raising in before_llm_call does not abort" do
    exploding = build_hook(before_llm_call: ->(chat:, last_tool_calls:) { raise "boom" })

    response = nil
    with_hooks(agent: [ exploding ]) do
      response, _hooks = with_stub_step { run_step_with_hooks }
    end

    assert_respond_to response, :tool_call?
  end

  private

  def run_step_with_hooks
    context_user_message_id = @chat.messages.where(role: "user").maximum(:id)
    Daan::Core::Chats::RunStepWithHooks.call(@chat, context_user_message_id: context_user_message_id)
  end

  def with_stub_step
    step_response = OpenStruct.new("tool_call?" => false, role: "assistant", tool_calls: nil)
    step_callable = ->(*) {
      @chat.messages.create!(role: "assistant", content: "Hello human")
      step_response
    }
    Daan::Core::Chats::ConfigureLlm.stub(:call, nil) do
      @chat.stub(:step, step_callable) { yield }
    end
  end

  def build_hook(**callbacks)
    Class.new do
      include Daan::Core::Hook
      callbacks.each do |name, callable|
        define_method(name) { |**args| callable.call(**args) }
      end
    end.new
  end

  def with_hooks(agent: [], tool: [])
    Daan::Core::Hook::Registry.stub(:agent_hooks, agent) do
      Daan::Core::Hook::Registry.stub(:tool_hooks, tool) do
        yield
      end
    end
  end
end
