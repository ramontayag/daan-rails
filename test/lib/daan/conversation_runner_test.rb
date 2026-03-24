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

  test "re-enqueues LlmJob when response has tool calls" do
    @chat.start!
    agent = Daan::AgentRegistry.find(@chat.agent_name)
    tool_response = OpenStruct.new("tool_call?" => true, role: "assistant", tool_calls: {})

    assert_enqueued_with(job: LlmJob, args: [ @chat ]) do
      Daan::ConversationRunner.send(:finish_or_reenqueue, @chat, agent, tool_response)
    end
  end

  test "calls finish_conversation when response has no tool calls" do
    @chat.start!
    agent = Daan::AgentRegistry.find(@chat.agent_name)
    final_response = OpenStruct.new("tool_call?" => false, role: "assistant", tool_calls: {})

    Daan::ConversationRunner.send(:finish_or_reenqueue, @chat, agent, final_response)

    assert @chat.reload.completed?
  end

  test "injects relevant memories into system prompt when memories exist" do
    fake_results = [
      { file_path: "fact/rails/db.md", title: "Rails uses SQLite", score: 0.9,
        metadata: { "type" => "fact", "confidence" => "high" } }
    ]

    captured_prompt = nil
    @chat.define_singleton_method(:with_instructions) do |prompt|
      captured_prompt = prompt
      self
    end

    with_stub_memories(fake_results) do
      with_stub_step { Daan::ConversationRunner.call(@chat) }
    end

    assert_includes captured_prompt, "Rails uses SQLite"
    assert_includes captured_prompt, "## Relevant memories"
    assert_includes captured_prompt, "fact/rails/db.md"
  ensure
    if @chat.singleton_class.method_defined?(:with_instructions, false)
      @chat.singleton_class.remove_method(:with_instructions)
    end
  end

  test "does not alter system prompt when no memories exist" do
    captured_prompt = nil
    @chat.define_singleton_method(:with_instructions) do |prompt|
      captured_prompt = prompt
      self
    end

    with_stub_memories([]) do
      with_stub_step { Daan::ConversationRunner.call(@chat) }
    end

    assert_equal "You are a test agent.", captured_prompt
  ensure
    if @chat.singleton_class.method_defined?(:with_instructions, false)
      @chat.singleton_class.remove_method(:with_instructions)
    end
  end

  test "memory retrieval failure does not crash the runner" do
    storage_stub = Object.new
    storage_stub.define_singleton_method(:semantic_index) { raise "embed error" }
    msc = Daan::Memory.singleton_class
    msc.alias_method(:__orig_storage__, :storage)
    msc.define_method(:storage) { storage_stub }
    with_stub_step { Daan::ConversationRunner.call(@chat) }
    assert @chat.reload.completed?
  ensure
    msc.alias_method(:storage, :__orig_storage__)
    msc.remove_method(:__orig_storage__)
  end

  # -- Already-responded guard tests --

  test "does not call step when assistant response covers the last user message" do
    last_user_message = @chat.messages.where(role: "user").last
    @chat.messages.create!(role: "assistant", content: "Already handled",
                           context_user_message_id: last_user_message.id)

    step_called = false
    @chat.define_singleton_method(:step) { |*| step_called = true }

    Daan::ConversationRunner.call(@chat)

    assert_not step_called, "expected step NOT to be called when response already recorded"
  ensure
    @chat.singleton_class.remove_method(:step) if @chat.singleton_class.method_defined?(:step, false)
  end

  test "does not change chat state when assistant response covers the last user message" do
    @chat.start!
    @chat.finish!
    last_user_message = @chat.messages.where(role: "user").last
    @chat.messages.create!(role: "assistant", content: "Already handled",
                           context_user_message_id: last_user_message.id)

    @chat.define_singleton_method(:step) { |*| OpenStruct.new("tool_call?" => false, role: "assistant") }

    Daan::ConversationRunner.call(@chat)

    assert @chat.reload.completed?, "expected chat to remain completed"
  ensure
    @chat.singleton_class.remove_method(:step) if @chat.singleton_class.method_defined?(:step, false)
  end

  test "calls step when assistant context_user_message_id predates a newer user message (race condition)" do
    # Simulates: Job1 ran and wrote a response with context_user_message_id pointing at
    # notification1, but notification2 arrived *during* that run (higher id). Job2 must
    # not be skipped — it needs to process notification2.
    notification1 = @chat.messages.where(role: "user").last
    @chat.messages.create!(role: "assistant", content: "Handled notification 1",
                           context_user_message_id: notification1.id)
    @chat.messages.create!(role: "user", content: "[System] notification 2")

    with_stub_step { Daan::ConversationRunner.call(@chat) }

    assert @chat.reload.completed?
  end

  test "calls step normally when last user message has no assistant response" do
    # Default setup: chat has only a user message — normal flow should proceed
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
    @chat.define_singleton_method(:step) { |*| raise "LLM down" }
    assert_raises(RuntimeError) { Daan::ConversationRunner.call(@chat) }

    notification = parent_chat.messages.find_by("content LIKE ?", "%thread is now failed%")
    assert notification, "expected parent notification on failure"
    assert_includes notification.content, "No response recorded."
  ensure
    @chat.singleton_class.remove_method(:step) if @chat.singleton_class.method_defined?(:step, false)
  end

  test "enqueues CompactJob when token count exceeds 80% of context window" do
    @chat.messages.where(compacted_message_id: nil).delete_all
    25.times do |i|
      @chat.messages.create!(role: i.even? ? "user" : "assistant",
                             content: "message #{i}", output_tokens: 40)
    end
    # 25 * 40 = 1000 tokens; 80% of 1000 = 800 → triggers compaction

    @chat.define_singleton_method(:model) { OpenStruct.new(context_window: 1000) }
    assert_enqueued_with(job: CompactJob) do
      Daan::ConversationRunner.send(:enqueue_compaction_if_needed, @chat)
    end
  ensure
    @chat.singleton_class.remove_method(:model) if @chat.singleton_class.method_defined?(:model, false)
  end

  test "does not enqueue CompactJob when token count is below threshold" do
    @chat.messages.where(compacted_message_id: nil).delete_all
    @chat.messages.create!(role: "user", content: "hi", output_tokens: 10)

    @chat.define_singleton_method(:model) { OpenStruct.new(context_window: 1000) }
    assert_no_enqueued_jobs(only: CompactJob) do
      Daan::ConversationRunner.send(:enqueue_compaction_if_needed, @chat)
    end
  ensure
    @chat.singleton_class.remove_method(:model) if @chat.singleton_class.method_defined?(:model, false)
  end

  # Temporarily override retrieve_memories using alias/restore on the singleton class.
  def with_stub_memories(results, &block)
    sc = Daan::ConversationRunner.singleton_class
    sc.alias_method(:__orig_retrieve_memories__, :retrieve_memories)
    sc.define_method(:retrieve_memories) { |_chat| results }
    block.call
  ensure
    sc.alias_method(:retrieve_memories, :__orig_retrieve_memories__)
    sc.remove_method(:__orig_retrieve_memories__)
  end

  def with_stub_tool_step(&block)
    @chat.define_singleton_method(:step) do |*|
      messages.create!(role: "assistant", content: "Hello human")
      OpenStruct.new("tool_call?" => true, role: "assistant", tool_calls: {})
    end
    block.call
  ensure
    @chat.singleton_class.remove_method(:step) if @chat.singleton_class.method_defined?(:step, false)
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

  def with_stub_step(raise_error: nil, &block)
    called = false
    step_response = OpenStruct.new("tool_call?" => false, role: "assistant", tool_calls: nil)
    @chat.define_singleton_method(:step) do |*|
      called = true
      raise raise_error if raise_error
      messages.create!(role: "assistant", content: "Hello human")
      step_response
    end
    block.call
    assert called, "expected step to be called" unless raise_error
  ensure
    @chat.singleton_class.remove_method(:step) if @chat.singleton_class.method_defined?(:step, false)
  end
end
