# test/lib/daan/conversation_runner_test.rb
require "test_helper"
require "ostruct"

class Daan::ConversationRunnerTest < ActiveSupport::TestCase
  include ActionCable::TestHelper
  include ActiveJob::TestHelper

  setup do
    @agent = Daan::Agent.new(
      name: "test_agent", display_name: "Test Agent",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You are a test agent.",
      max_steps: 3
    )
    Daan::AgentRegistry.register(@agent)
    @chat = Chat.create!(agent_name: "test_agent")
    @chat.messages.create!(role: "user", content: "Hello agent")
  end

  teardown { Daan::Core::Hook::Registry.clear }

  test "transitions to completed" do
    with_stub_step { Daan::ConversationRunner.call(@chat) }
    assert @chat.reload.completed?
  end

  test "step_count reflects assistant messages since last user message" do
    with_stub_step { Daan::ConversationRunner.call(@chat) }
    assert_equal 1, @chat.reload.step_count
  end

  test "transitions to blocked when max_steps reached and agent wants to continue" do
    # Simulate max_steps - 1 prior tool-call steps (each produces assistant + tool result)
    prior_steps(@agent.max_steps - 1)
    # Agent returns a tool call (wants to continue), but limit is reached
    with_stub_tool_step { Daan::ConversationRunner.call(@chat) }
    assert @chat.reload.blocked?
  end

  test "completes normally when agent finishes on step max_steps" do
    # If the agent produces a final answer exactly at the limit, it should complete not block
    prior_steps(@agent.max_steps - 1)
    with_stub_step { Daan::ConversationRunner.call(@chat) }
    assert @chat.reload.completed?
  end

  test "re-triggers a completed chat by calling continue! before start!" do
    @chat.start!
    @chat.finish!
    with_stub_step { Daan::ConversationRunner.call(@chat) }
    assert @chat.reload.completed?
  end

  test "re-triggers a blocked chat by calling continue! before start!" do
    @chat.start!
    @chat.block!
    with_stub_step { Daan::ConversationRunner.call(@chat) }
    assert @chat.reload.completed?
  end

  test "re-triggers a failed chat by calling continue! before start!" do
    @chat.fail!
    with_stub_step { Daan::ConversationRunner.call(@chat) }
    assert @chat.reload.completed?
  end

  test "transitions to failed and reraises on exception" do
    with_stub_step(raise_error: RuntimeError.new("LLM down")) do
      assert_raises(RuntimeError) { Daan::ConversationRunner.call(@chat) }
    end
    assert @chat.reload.failed?
  end

  test "broadcasts typing indicator on start, appends step message, and turns typing off on finish" do
    with_stub_step do
      assert_broadcasts("chat_#{@chat.id}", 5) do
        Daan::ConversationRunner.call(@chat)
      end
    end
  end

  test "BroadcastMessagesJob is gone" do
    refute defined?(BroadcastMessagesJob), "BroadcastMessagesJob should be deleted"
  end

  # -- Already-responded guard tests --

  test "does not call step when assistant response covers the last user message" do
    last_user_message = @chat.messages.where(role: "user").last
    @chat.messages.create!(role: "assistant", content: "Already handled",
                           context_user_message_id: last_user_message.id)

    step_called = false
    @chat.stub(:step, ->(*) { step_called = true }) do
      Daan::ConversationRunner.call(@chat)
    end
    assert_not step_called, "expected step NOT to be called when response already recorded"
  end

  test "does not change chat state when assistant response covers the last user message" do
    @chat.start!
    @chat.finish!
    last_user_message = @chat.messages.where(role: "user").last
    @chat.messages.create!(role: "assistant", content: "Already handled",
                           context_user_message_id: last_user_message.id)

    step_response = OpenStruct.new("tool_call?" => false, role: "assistant")
    @chat.stub(:step, step_response) do
      Daan::ConversationRunner.call(@chat)
    end
    assert @chat.reload.completed?, "expected chat to remain completed"
  end

  test "calls step when assistant context_user_message_id predates a newer user message (race condition)" do
    notification1 = @chat.messages.where(role: "user").last
    @chat.messages.create!(role: "assistant", content: "Handled notification 1",
                           context_user_message_id: notification1.id)
    @chat.messages.create!(role: "user", content: "[System] notification 2")

    with_stub_step { Daan::ConversationRunner.call(@chat) }

    assert @chat.reload.completed?
  end

  test "calls step normally when last user message has no assistant response" do
    with_stub_step { Daan::ConversationRunner.call(@chat) }
    assert @chat.reload.completed?
  end

  test "sets context_user_message_id on the assistant message it creates" do
    last_user_message = @chat.messages.where(role: "user").last

    with_stub_step { Daan::ConversationRunner.call(@chat) }

    assistant_message = @chat.messages.where(role: "assistant").last
    assert_equal last_user_message.id, assistant_message.context_user_message_id
  end


  # -- Turn limit warning & parent notification tests --

  test "injects warning when 3 steps remain and agent wants to continue" do
    parent_agent = Daan::Agent.new(
      name: "parent_agent", display_name: "Parent Agent",
      model_name: "claude-sonnet-4-20250514", system_prompt: "Parent.", max_steps: 15
    )
    Daan::AgentRegistry.register(parent_agent)
    parent_chat = Chat.create!(agent_name: "parent_agent")
    @chat.update!(parent_chat: parent_chat)

    @agent.max_steps = 10
    # Simulate 6 prior tool-call steps; after this step step_count = 7, remaining = 3
    prior_steps(6)

    # Agent returns a tool call (wants to continue) — triggers warning path
    with_stub_tool_step { Daan::ConversationRunner.call(@chat) }

    warning = @chat.messages.find_by("content LIKE ?", "%2 steps of work remaining%")
    assert warning, "expected step-limit warning message"
    assert_equal "user", warning.role
    assert_equal false, warning.visible
  end

  test "does not inject warning for top-level chat (no parent)" do
    @agent.max_steps = 10
    prior_steps(6)

    with_stub_tool_step { Daan::ConversationRunner.call(@chat) }

    warning = @chat.messages.find_by("content LIKE ?", "%2 steps of work remaining%")
    assert_nil warning
  end

  test "notifies parent when child chat goes blocked" do
    parent_agent = Daan::Agent.new(
      name: "parent_agent", display_name: "Parent Agent",
      model_name: "claude-sonnet-4-20250514", system_prompt: "Parent.", max_steps: 15
    )
    Daan::AgentRegistry.register(parent_agent)
    parent_chat = Chat.create!(agent_name: "parent_agent")
    @chat.update!(parent_chat: parent_chat)
    prior_steps(@agent.max_steps - 1)

    with_stub_tool_step { Daan::ConversationRunner.call(@chat) }

    assert @chat.reload.blocked?
    notification = parent_chat.messages.find_by("content LIKE ?", "%thread is now blocked%")
    assert notification, "expected parent notification"
    assert_equal "user", notification.role
    assert_equal false, notification.visible
    assert_includes notification.content, "Test Agent"
    assert_includes notification.content, "maximum step limit"
    assert_includes notification.content, "Hello human" # from with_stub_tool_step
  end

  test "notifies parent when child chat fails" do
    parent_agent = Daan::Agent.new(
      name: "parent_agent", display_name: "Parent Agent",
      model_name: "claude-sonnet-4-20250514", system_prompt: "Parent.", max_steps: 15
    )
    Daan::AgentRegistry.register(parent_agent)
    parent_chat = Chat.create!(agent_name: "parent_agent")
    @chat.update!(parent_chat: parent_chat)

    with_stub_step(raise_error: RuntimeError.new("LLM down")) do
      assert_raises(RuntimeError) { Daan::ConversationRunner.call(@chat) }
    end

    assert @chat.reload.failed?
    notification = parent_chat.messages.find_by("content LIKE ?", "%thread is now failed%")
    assert notification, "expected parent notification on failure"
    assert_includes notification.content, "error occurred"
  end

  test "does not notify parent when top-level chat goes blocked" do
    prior_steps(@agent.max_steps - 1)

    with_stub_tool_step { Daan::ConversationRunner.call(@chat) }

    assert @chat.reload.blocked?
    # No parent, so no notification anywhere. Just verify no crash.
  end

  test "parent notification uses fallback when last assistant message is nil" do
    parent_agent = Daan::Agent.new(
      name: "parent_agent", display_name: "Parent Agent",
      model_name: "claude-sonnet-4-20250514", system_prompt: "Parent.", max_steps: 15
    )
    Daan::AgentRegistry.register(parent_agent)
    parent_chat = Chat.create!(agent_name: "parent_agent")
    @chat.update!(parent_chat: parent_chat)

    # Step fails without creating any assistant messages — triggers failed path
    @chat.stub(:step, ->(*) { raise "LLM down" }) do
      assert_raises(RuntimeError) { Daan::ConversationRunner.call(@chat) }
    end
    notification = parent_chat.messages.find_by("content LIKE ?", "%thread is now failed%")
    assert notification, "expected parent notification on failure"
    assert_includes notification.content, "No response recorded."
  end

  test "calls before_llm_call on agent's hooks with chat and last_tool_calls" do
    received_args = nil
    spy_hook = Class.new do
      include Daan::Core::Hook
      define_method(:before_llm_call) { |chat:, last_tool_calls:| received_args = { chat: chat, last_tool_calls: last_tool_calls } }
    end

    Daan::Core::Hook::Registry.stub(:agent_hooks, [ spy_hook.new ]) do
      Daan::Core::Hook::Registry.stub(:tool_hooks, []) do
        with_stub_step { Daan::ConversationRunner.call(@chat) }
      end
    end

    assert_not_nil received_args
    assert_equal @chat, received_args[:chat]
    assert_respond_to received_args[:last_tool_calls], :each
  end

  test "a hook that raises does not abort the conversation" do
    exploding_hook = Class.new do
      include Daan::Core::Hook
      def before_llm_call(chat:, last_tool_calls:) = raise "boom"
    end

    Daan::Core::Hook::Registry.stub(:agent_hooks, [ exploding_hook.new ]) do
      Daan::Core::Hook::Registry.stub(:tool_hooks, []) do
        with_stub_step { Daan::ConversationRunner.call(@chat) }
      end
    end

    assert @chat.reload.completed?
  end

  test "dispatches before_conversation when step_count is 0 (first LLM step)" do
    received = nil
    spy = Class.new do
      include Daan::Core::Hook
      define_method(:before_conversation) { |chat:| received = chat }
    end

    Daan::Core::Hook::Registry.stub(:agent_hooks, [ spy.new ]) do
      Daan::Core::Hook::Registry.stub(:tool_hooks, []) do
        with_stub_step { Daan::ConversationRunner.call(@chat) }
      end
    end

    assert_equal @chat, received
  end

  test "does not dispatch before_conversation on subsequent steps (step_count > 0)" do
    prior_steps(1)  # creates one assistant message after the user message → step_count = 1
    called = false
    spy = Class.new do
      include Daan::Core::Hook
      define_method(:before_conversation) { |chat:| called = true }
    end

    Daan::Core::Hook::Registry.stub(:agent_hooks, [ spy.new ]) do
      Daan::Core::Hook::Registry.stub(:tool_hooks, []) do
        with_stub_step { Daan::ConversationRunner.call(@chat) }
      end
    end

    assert_not called, "before_conversation must not fire on step 2+"
  end

  test "sets Thread.current[:daan_active_hooks] during RunStep execution" do
    captured = nil
    # Replace RunStep.call so we can inspect thread state mid-execution
    Daan::Chats::RunStep.stub(:call, ->(chat, **) {
      captured = Thread.current[:daan_active_hooks]
      OpenStruct.new("tool_call?" => false, role: "assistant")
    }) do
      Daan::ConversationRunner.call(@chat)
    end
    assert_not_nil captured, "expected [:daan_active_hooks] to be set during RunStep"
    assert_respond_to captured[:hooks], :each
    assert_equal @chat, captured[:chat]
  end

  test "clears Thread.current[:daan_active_hooks] after RunStep" do
    Daan::Chats::RunStep.stub(:call, ->(*) {
      OpenStruct.new("tool_call?" => false, role: "assistant")
    }) do
      Daan::ConversationRunner.call(@chat)
    end
    assert_nil Thread.current[:daan_active_hooks]
  end

  test "clears Thread.current[:daan_active_hooks] even when RunStep raises" do
    Daan::Chats::RunStep.stub(:call, ->(*) { raise RuntimeError, "boom" }) do
      assert_raises(RuntimeError) { Daan::ConversationRunner.call(@chat) }
    end
    assert_nil Thread.current[:daan_active_hooks]
  end

  test "dispatches after_conversation(:completed) when chat finishes" do
    received = nil
    spy = Class.new do
      include Daan::Core::Hook
      define_method(:after_conversation) { |chat:, status:| received = { chat: chat, status: status } }
    end

    Daan::Core::Hook::Registry.stub(:agent_hooks, [ spy.new ]) do
      Daan::Core::Hook::Registry.stub(:tool_hooks, []) do
        with_stub_step { Daan::ConversationRunner.call(@chat) }
      end
    end

    assert_not_nil received
    assert_equal :completed, received[:status]
  end

  test "dispatches after_conversation(:blocked) when max steps reached" do
    received_status = nil
    spy = Class.new do
      include Daan::Core::Hook
      define_method(:after_conversation) { |chat:, status:| received_status = status }
    end

    prior_steps(@agent.max_steps - 1)

    Daan::Core::Hook::Registry.stub(:agent_hooks, [ spy.new ]) do
      Daan::Core::Hook::Registry.stub(:tool_hooks, []) do
        with_stub_tool_step { Daan::ConversationRunner.call(@chat) }
      end
    end

    assert_equal :blocked, received_status
  end

  test "dispatches after_conversation(:failed) when RunStep raises" do
    received_status = nil
    spy = Class.new do
      include Daan::Core::Hook
      define_method(:after_conversation) { |chat:, status:| received_status = status }
    end

    Daan::Core::Hook::Registry.stub(:agent_hooks, [ spy.new ]) do
      Daan::Core::Hook::Registry.stub(:tool_hooks, []) do
        with_stub_step(raise_error: RuntimeError.new("LLM down")) do
          assert_raises(RuntimeError) { Daan::ConversationRunner.call(@chat) }
        end
      end
    end

    assert_equal :failed, received_status
  end

  test "does not dispatch after_conversation when chat is re-enqueued mid-conversation" do
    called = false
    spy = Class.new do
      include Daan::Core::Hook
      define_method(:after_conversation) { |chat:, status:| called = true }
    end

    # Tool call step, max_steps NOT reached — LlmJob re-enqueued, chat stays in_progress
    Daan::Core::Hook::Registry.stub(:agent_hooks, [ spy.new ]) do
      Daan::Core::Hook::Registry.stub(:tool_hooks, []) do
        with_stub_tool_step { Daan::ConversationRunner.call(@chat) }
      end
    end

    assert_not called, "after_conversation must not fire when LlmJob is re-enqueued"
  end

  test "ripple-check message injected when agent has shaping hook and update_document was called" do
    @agent.hook_names = [ "Daan::Core::Shaping" ]

    assistant = @chat.messages.create!(role: "assistant", content: "Updating doc")
    ToolCall.create!(message: assistant, name: Daan::Core::UpdateDocument.tool_name,
                     tool_call_id: SecureRandom.hex(8))

    with_stub_step { Daan::ConversationRunner.call(@chat) }

    ripple = @chat.messages.where_content_like("%Ripple check%").first
    assert ripple, "expected ripple check message"
    assert_equal false, ripple.visible
    assert_equal "user", ripple.role
  end

  def with_stub_tool_step
    chat = @chat
    step_callable = ->(*) {
      chat.messages.create!(role: "assistant", content: "Hello human")
      OpenStruct.new("tool_call?" => true, role: "assistant", tool_calls: {})
    }
    @chat.stub(:step, step_callable) { yield }
  end

  # Simulate n completed tool-call steps. Each step produces an assistant message
  # (the tool call) followed by a tool result — matching real conversation state.
  # After n steps the last message is a tool result, so already_responded? stays false.
  def prior_steps(n)
    n.times do
      assistant_msg = @chat.messages.create!(role: "assistant", content: "prior step")
      tool_call = ToolCall.create!(message: assistant_msg, name: "some_tool",
                                   tool_call_id: SecureRandom.hex(8))
      @chat.messages.create!(role: "tool", tool_call_id: tool_call.id, content: "result")
    end
  end

  def with_stub_step(raise_error: nil)
    called = false
    chat = @chat
    step_response = OpenStruct.new("tool_call?" => false, role: "assistant", tool_calls: nil)
    step_callable = ->(*) {
      called = true
      raise raise_error if raise_error
      chat.messages.create!(role: "assistant", content: "Hello human")
      step_response
    }
    @chat.stub(:step, step_callable) do
      yield
      assert called, "expected step to be called" unless raise_error
    end
  end
end
