# test/lib/daan/core/delegate_task_test.rb
require "test_helper"

class Daan::Core::DelegateTaskTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    RubyLLM::Models.instance.load_from_json!
    Daan::Core::AgentRegistry.register(
      build_agent(name: "chief_of_staff", display_name: "Chief of Staff",
                      delegates_to: [ "engineering_manager" ])
    )
    Daan::Core::AgentRegistry.register(
      build_agent(name: "engineering_manager", display_name: "Engineering Manager")
    )
    @parent_chat = Chat.create!(agent_name: "chief_of_staff")
    @tool = Daan::Core::DelegateTask.new(chat: @parent_chat)
  end

  test "creates a sub-chat for the target agent" do
    assert_difference "Chat.count", 1 do
      @tool.execute(agent_name: "engineering_manager", task: "Do the thing")
    end
    sub_chat = Chat.last
    assert_equal "engineering_manager", sub_chat.agent_name
    assert_equal @parent_chat, sub_chat.parent_chat
  end

  test "creates a user message in the sub-chat" do
    @tool.execute(agent_name: "engineering_manager", task: "Do the thing")
    msg = Chat.last.messages.first
    assert_equal "user", msg.role
    assert_equal "Do the thing", msg.content
  end

  test "enqueues LlmJob for the sub-chat" do
    assert_enqueued_with(job: LlmJob) do
      @tool.execute(agent_name: "engineering_manager", task: "Do the thing")
    end
  end

  test "returns a delegation confirmation string" do
    result = @tool.execute(agent_name: "engineering_manager", task: "Do the thing")
    assert_includes result, "Engineering Manager"
    assert_includes result, "Awaiting"
  end

  test "returns error string when agent is not in delegates_to" do
    result = @tool.execute(agent_name: "developer", task: "Do the thing")
    assert_includes result, "Error"
    assert_includes result, "engineering_manager"
  end

  test "returns follow-up confirmation string when thread already exists" do
    @tool.execute(agent_name: "engineering_manager", task: "First task")
    result = @tool.execute(agent_name: "engineering_manager", task: "Follow up")
    assert_includes result, "follow-up"
    assert_includes result, "Engineering Manager"
  end

  test "reuses existing sub-chat for the same agent" do
    @tool.execute(agent_name: "engineering_manager", task: "First task")
    assert_no_difference "Chat.count" do
      @tool.execute(agent_name: "engineering_manager", task: "Follow up")
    end
  end

  test "posts a new message into the existing sub-chat on follow-up" do
    @tool.execute(agent_name: "engineering_manager", task: "First task")
    sub_chat = @parent_chat.sub_chats.find_by!(agent_name: "engineering_manager")
    @tool.execute(agent_name: "engineering_manager", task: "Follow up")
    assert_equal 2, sub_chat.messages.where(role: "user").count
    assert_equal "Follow up", sub_chat.messages.where(role: "user").last.content
  end

  test "resets a failed sub-chat to pending before adding the follow-up message" do
    @tool.execute(agent_name: "engineering_manager", task: "First task")
    sub_chat = @parent_chat.sub_chats.find_by!(agent_name: "engineering_manager")
    sub_chat.update!(task_status: "failed")

    @tool.execute(agent_name: "engineering_manager", task: "Follow up")

    assert sub_chat.reload.pending?
  end

  test "assigns the target agent's model to the new sub-chat" do
    Daan::Core::AgentRegistry.register(
      build_agent(name: "developer",
                      model_name: "claude-haiku-4-5-20251001")
    )
    Daan::Core::AgentRegistry.register(
      build_agent(name: "chief_of_staff",
                      delegates_to: [ "engineering_manager", "developer" ])
    )
    parent_chat = Chat.create!(agent_name: "chief_of_staff")
    tool = Daan::Core::DelegateTask.new(chat: parent_chat)

    tool.execute(agent_name: "developer", task: "Build something")

    sub_chat = parent_chat.sub_chats.find_by!(agent_name: "developer")
    assert_equal "claude-haiku-4-5-20251001", sub_chat.model&.model_id
  end

  test "raises when target agent is in delegates_to but absent from registry" do
    Daan::Core::AgentRegistry.register(
      build_agent(name: "ghost_delegator",
                      delegates_to: [ "phantom_agent" ])
    )
    ghost_chat = Chat.create!(agent_name: "ghost_delegator")
    tool = Daan::Core::DelegateTask.new(chat: ghost_chat)
    assert_raises(Daan::Core::AgentNotFoundError) { tool.execute(agent_name: "phantom_agent", task: "do it") }
  end
end
