# test/lib/daan/chats/build_system_prompt_test.rb
require "test_helper"

class Daan::Core::Chats::BuildSystemPromptTest < ActiveSupport::TestCase
  setup do
    Daan::Core::AgentRegistry.register(
      Daan::Core::Agent.new(
        name: "developer", display_name: "Developer",
        model_name: "claude-sonnet-4-20250514",
        system_prompt: "You are a developer.", max_steps: 10
      )
    )
    @chat = Chat.create!(agent_name: "developer")
    @agent = @chat.agent
  end

  # -- Audience --

  test "appends human audience context for top-level chat" do
    prompt = with_stub_memories([]) { Daan::Core::Chats::BuildSystemPrompt.call(@chat, @agent) }

    assert_includes prompt, "You are talking directly to the human."
  end

  test "appends agent audience context for delegated chat" do
    Daan::Core::AgentRegistry.register(
      Daan::Core::Agent.new(
        name: "engineering_manager", display_name: "Engineering Manager",
        model_name: "m", system_prompt: "p", max_steps: 10
      )
    )
    parent = Chat.create!(agent_name: "engineering_manager")
    child = Chat.create!(agent_name: "developer", parent_chat: parent)

    prompt = with_stub_memories([]) { Daan::Core::Chats::BuildSystemPrompt.call(child, child.agent) }

    assert_includes prompt, "delegated this task by Engineering Manager"
  end

  # -- Steps --

  test "appends steps to system prompt when steps exist" do
    ChatStep.create!(chat: @chat, title: "Clone repo", position: 1, status: "completed")
    ChatStep.create!(chat: @chat, title: "Write tests", position: 2, status: "in_progress")
    ChatStep.create!(chat: @chat, title: "Implement", position: 3)

    prompt = with_stub_memories([]) { Daan::Core::Chats::BuildSystemPrompt.call(@chat, @agent) }

    assert_includes prompt, "You are a developer."
    assert_includes prompt, "## Your Current Steps"
    assert_includes prompt, "1. [x] Clone repo"
    assert_includes prompt, "2. [in progress] Write tests"
    assert_includes prompt, "3. [ ] Implement"
  end

  test "does not append steps section when no steps exist" do
    prompt = with_stub_memories([]) { Daan::Core::Chats::BuildSystemPrompt.call(@chat, @agent) }

    assert_includes prompt, "You are a developer."
    assert_not_includes prompt, "Your Current Steps"
  end

  # -- Memories --

  test "injects relevant memories into system prompt when memories exist" do
    fake_results = [
      { file_path: "fact/rails/db.md", title: "Rails uses SQLite", score: 0.9,
        metadata: { "type" => "fact", "confidence" => "high" } }
    ]

    prompt = with_stub_memories(fake_results) { Daan::Core::Chats::BuildSystemPrompt.call(@chat, @agent) }

    assert_includes prompt, "Rails uses SQLite"
    assert_includes prompt, "## Relevant memories"
    assert_includes prompt, "fact/rails/db.md"
  end

  test "does not append memories section when no memories exist" do
    prompt = with_stub_memories([]) { Daan::Core::Chats::BuildSystemPrompt.call(@chat, @agent) }

    assert_includes prompt, "You are a developer."
    assert_not_includes prompt, "Relevant memories"
  end

  test "memory retrieval failure does not crash and returns base prompt" do
    storage_stub = Object.new
    storage_stub.define_singleton_method(:semantic_index) { raise "embed error" }

    Daan::Core::Memory.stub(:storage, storage_stub) do
      @chat.messages.create!(role: "user", content: "hello")
      prompt = Daan::Core::Chats::BuildSystemPrompt.call(@chat, @agent)
      assert_includes prompt, "You are a developer."
    end
  end

  private

  def with_stub_memories(results)
    Daan::Core::Chats::BuildSystemPrompt.stub(:retrieve_memories, results) { yield }
  end
end
