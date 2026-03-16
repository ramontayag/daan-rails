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
      max_turns: 3
    )
    Daan::AgentRegistry.register(@agent)
    @chat = Chat.create!(agent_name: "test_agent")
    @chat.messages.create!(role: "user", content: "Hello agent")
  end

  test "transitions to completed" do
    with_stub_complete { Daan::ConversationRunner.call(@chat) }
    assert @chat.reload.completed?
  end

  test "increments turn_count" do
    with_stub_complete { Daan::ConversationRunner.call(@chat) }
    assert_equal 1, @chat.reload.turn_count
  end

  test "transitions to blocked when max_turns reached" do
    @chat.update!(turn_count: @agent.max_turns - 1)
    with_stub_complete { Daan::ConversationRunner.call(@chat) }
    assert @chat.reload.blocked?
  end

  test "re-triggers a completed chat by calling continue! before start!" do
    @chat.start!
    @chat.finish!
    with_stub_complete { Daan::ConversationRunner.call(@chat) }
    assert @chat.reload.completed?
  end

  test "re-triggers a blocked chat by calling continue! before start!" do
    @chat.start!
    @chat.block!
    with_stub_complete { Daan::ConversationRunner.call(@chat) }
    assert @chat.reload.completed?
  end

  test "re-triggers a failed chat by calling continue! before start!" do
    @chat.fail!
    with_stub_complete { Daan::ConversationRunner.call(@chat) }
    assert @chat.reload.completed?
  end

  test "transitions to failed and reraises on exception" do
    with_stub_complete(raise_error: RuntimeError.new("LLM down")) do
      assert_raises(RuntimeError) { Daan::ConversationRunner.call(@chat) }
    end
    assert @chat.reload.failed?
  end

  test "broadcasts typing on and off, and enqueues BroadcastMessagesJob" do
    with_stub_complete do
      assert_broadcasts("chat_#{@chat.id}", 2) do
        assert_enqueued_with(job: BroadcastMessagesJob) do
          Daan::ConversationRunner.call(@chat)
        end
      end
    end
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
      with_stub_complete { Daan::ConversationRunner.call(@chat) }
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
      with_stub_complete { Daan::ConversationRunner.call(@chat) }
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
    with_stub_complete { Daan::ConversationRunner.call(@chat) }
    assert @chat.reload.completed?
  ensure
    msc.alias_method(:storage, :__orig_storage__)
    msc.remove_method(:__orig_storage__)
  end

  # -- Turn limit warning & parent notification tests --

  test "injects warning when 3 turns remain and chat has parent" do
    parent_agent = Daan::Agent.new(
      name: "parent_agent", display_name: "Parent Agent",
      model_name: "claude-sonnet-4-20250514", system_prompt: "Parent.", max_turns: 15
    )
    Daan::AgentRegistry.register(parent_agent)
    parent_chat = Chat.create!(agent_name: "parent_agent")
    @chat.update!(parent_chat: parent_chat)

    @agent.max_turns = 10
    @chat.update!(turn_count: 6) # after increment: 7, remaining: 10-7=3

    with_stub_complete { Daan::ConversationRunner.call(@chat) }

    warning = @chat.messages.find_by("content LIKE ?", "%2 turns of work remaining%")
    assert warning, "expected turn-limit warning message"
    assert_equal "user", warning.role
    assert_equal false, warning.visible
  end

  test "does not inject warning for top-level chat (no parent)" do
    @agent.max_turns = 10
    @chat.update!(turn_count: 6)

    with_stub_complete { Daan::ConversationRunner.call(@chat) }

    warning = @chat.messages.find_by("content LIKE ?", "%2 turns of work remaining%")
    assert_nil warning
  end

  test "notifies parent when child chat goes blocked" do
    parent_agent = Daan::Agent.new(
      name: "parent_agent", display_name: "Parent Agent",
      model_name: "claude-sonnet-4-20250514", system_prompt: "Parent.", max_turns: 15
    )
    Daan::AgentRegistry.register(parent_agent)
    parent_chat = Chat.create!(agent_name: "parent_agent")
    @chat.update!(parent_chat: parent_chat, turn_count: @agent.max_turns - 1)

    with_stub_complete { Daan::ConversationRunner.call(@chat) }

    assert @chat.reload.blocked?
    notification = parent_chat.messages.find_by("content LIKE ?", "%thread is now blocked%")
    assert notification, "expected parent notification"
    assert_equal "user", notification.role
    assert_equal false, notification.visible
    assert_includes notification.content, "Test Agent"
    assert_includes notification.content, "maximum turn limit"
    assert_includes notification.content, "Hello human" # from with_stub_complete
  end

  test "notifies parent when child chat fails" do
    parent_agent = Daan::Agent.new(
      name: "parent_agent", display_name: "Parent Agent",
      model_name: "claude-sonnet-4-20250514", system_prompt: "Parent.", max_turns: 15
    )
    Daan::AgentRegistry.register(parent_agent)
    parent_chat = Chat.create!(agent_name: "parent_agent")
    @chat.update!(parent_chat: parent_chat)

    with_stub_complete(raise_error: RuntimeError.new("LLM down")) do
      assert_raises(RuntimeError) { Daan::ConversationRunner.call(@chat) }
    end

    assert @chat.reload.failed?
    notification = parent_chat.messages.find_by("content LIKE ?", "%thread is now failed%")
    assert notification, "expected parent notification on failure"
    assert_includes notification.content, "error occurred"
  end

  test "does not notify parent when top-level chat goes blocked" do
    @chat.update!(turn_count: @agent.max_turns - 1)

    with_stub_complete { Daan::ConversationRunner.call(@chat) }

    assert @chat.reload.blocked?
    # No parent, so no notification anywhere. Just verify no crash.
  end

  test "parent notification uses fallback when last assistant message is nil" do
    parent_agent = Daan::Agent.new(
      name: "parent_agent", display_name: "Parent Agent",
      model_name: "claude-sonnet-4-20250514", system_prompt: "Parent.", max_turns: 15
    )
    Daan::AgentRegistry.register(parent_agent)
    parent_chat = Chat.create!(agent_name: "parent_agent")
    @chat.update!(parent_chat: parent_chat, turn_count: @agent.max_turns - 1)

    # Stub complete to NOT create an assistant message
    @chat.define_singleton_method(:complete) { |*| }
    Daan::ConversationRunner.call(@chat)

    notification = parent_chat.messages.find_by("content LIKE ?", "%thread is now blocked%")
    assert notification, "expected parent notification"
    assert_includes notification.content, "No response recorded."
  ensure
    @chat.singleton_class.remove_method(:complete) if @chat.singleton_class.method_defined?(:complete, false)
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

  def with_stub_complete(raise_error: nil, &block)
    called = false
    @chat.define_singleton_method(:complete) do |*|
      called = true
      raise raise_error if raise_error
      messages.create!(role: "assistant", content: "Hello human")
    end
    block.call
    assert called, "expected complete to be called" unless raise_error
  ensure
    @chat.singleton_class.remove_method(:complete)
  end

end
