# test/lib/daan/chats/notify_parent_test.rb
require "test_helper"

class Daan::Core::Chats::NotifyParentTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Daan::Core::AgentRegistry.register(
      build_agent(name: "child_agent", display_name: "Child Agent")
    )
    Daan::Core::AgentRegistry.register(
      build_agent(name: "parent_agent")
    )
    @parent_chat = Chat.create!(agent_name: "parent_agent")
    @child_chat = Chat.create!(agent_name: "child_agent", parent_chat: @parent_chat)
    @child_chat.messages.create!(role: "user", content: "Do the thing")
  end

  # -- on_completion --

  test "enqueues LlmJob for parent when child completes" do
    @child_chat.messages.create!(role: "assistant", content: "Child Agent: done")
    assert_enqueued_with(job: LlmJob, args: [ @parent_chat ]) do
      Daan::Core::Chats::NotifyParent.on_completion(@child_chat)
    end
  end

  test "creates a system message in parent when agent did not report back" do
    @child_chat.messages.create!(role: "assistant", content: "I finished without reporting back")
    Daan::Core::Chats::NotifyParent.on_completion(@child_chat)
    msg = @parent_chat.messages.find_by("content LIKE ?", "%completed their task without calling report_back%")
    assert msg
    assert_equal false, msg.visible
  end

  test "does not create a missing report_back message when agent did report back" do
    @child_chat.messages.create!(role: "assistant", content: "done")
    Daan::Core::CreateMessage.call(
      @parent_chat,
      role: "user",
      content: "[SYSTEM] Child Agent reported back: here are my findings",
      visible: false
    )
    Daan::Core::Chats::NotifyParent.on_completion(@child_chat)
    msg = @parent_chat.messages.find_by("content LIKE ?", "%completed their task without calling report_back%")
    assert_nil msg
  end

  test "does nothing when child has no parent" do
    orphan = Chat.create!(agent_name: "child_agent")
    assert_no_enqueued_jobs(only: LlmJob) do
      Daan::Core::Chats::NotifyParent.on_completion(orphan)
    end
  end

  # -- on_termination --

  test "creates blocked notification in parent and enqueues LlmJob" do
    @child_chat.messages.create!(role: "assistant", content: "Last words")
    assert_enqueued_with(job: LlmJob, args: [ @parent_chat ]) do
      Daan::Core::Chats::NotifyParent.on_termination(@child_chat, :blocked)
    end
    msg = @parent_chat.messages.find_by("content LIKE ?", "%thread is now blocked%")
    assert msg
    assert_includes msg.content, "maximum step limit"
  end

  test "creates failed notification in parent and enqueues LlmJob" do
    @child_chat.messages.create!(role: "assistant", content: "Last words")
    assert_enqueued_with(job: LlmJob, args: [ @parent_chat ]) do
      Daan::Core::Chats::NotifyParent.on_termination(@child_chat, :failed)
    end
    msg = @parent_chat.messages.find_by("content LIKE ?", "%thread is now failed%")
    assert msg
    assert_includes msg.content, "error occurred"
  end

  test "uses fallback text when no last assistant message exists" do
    Daan::Core::Chats::NotifyParent.on_termination(@child_chat, :failed)
    msg = @parent_chat.messages.find_by("content LIKE ?", "%thread is now failed%")
    assert_includes msg.content, "No response recorded."
  end

  test "does nothing when child has no parent on termination" do
    orphan = Chat.create!(agent_name: "child_agent")
    assert_no_enqueued_jobs(only: LlmJob) do
      Daan::Core::Chats::NotifyParent.on_termination(orphan, :blocked)
    end
  end
end
