require "test_helper"

class ThreadListComponentTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  setup do
    @agent = Daan::Core::AgentRegistry.register(
      Daan::Core::Agent.new(name: "chief_of_staff", display_name: "Chief of Staff",
                      model_name: "claude-3-5-haiku-20241022", system_prompt: "p", max_steps: 10)
    )
    @agent.define_singleton_method(:busy?) { false }
  end

  test "renders thread list column" do
    render_inline(ThreadListComponent.new(agent: @agent, chats: []))
    assert_includes rendered_content, "data-testid=\"thread-list-column\""
  end

  test "shows empty state when no chats" do
    render_inline(ThreadListComponent.new(agent: @agent, chats: []))
    assert_includes rendered_content, "No conversations yet."
  end

  test "renders each chat as a thread list item" do
    chats = 2.times.map { Chat.create!(agent_name: @agent.name) }
    render_inline(ThreadListComponent.new(agent: @agent, chats: chats))
    assert rendered_content.scan("data-testid=\"thread-list-item\"").size == 2
  end

  test "list is visible when no thread is open" do
    render_inline(ThreadListComponent.new(agent: @agent, chats: []))
    assert_includes rendered_content, "flex flex-col"
    assert_not_includes rendered_content, "hidden md:flex"
  end

  test "list is hidden on mobile when a thread is open" do
    chat = Chat.create!(agent_name: @agent.name)
    render_inline(ThreadListComponent.new(agent: @agent, chats: [ chat ], open_chat: chat))
    assert_includes rendered_content, "hidden md:flex"
  end

  test "passes open state to the open thread list item" do
    chat = Chat.create!(agent_name: @agent.name)
    render_inline(ThreadListComponent.new(agent: @agent, chats: [ chat ], open_chat: chat))
    assert_includes rendered_content, "bg-blue-50"
  end

  test "compose bar is readonly when readonly: true" do
    render_inline(ThreadListComponent.new(agent: @agent, chats: [], readonly: true))
    assert_includes rendered_content, "read-only"
  end
end
