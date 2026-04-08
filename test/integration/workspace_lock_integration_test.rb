require "test_helper"

class WorkspaceLockIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @agent = Daan::Core::Agent.new(
      name: "developer", display_name: "Dev",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You are a developer.", max_steps: 10,
      workspace: Daan::Core::Workspace.new(Dir.mktmpdir)
    )
    Daan::Core::AgentRegistry.register(@agent)
  end

  test "second chat waits when first chat holds workspace lock" do
    chat_a = Chat.create!(agent_name: "developer")
    chat_b = Chat.create!(agent_name: "developer")
    chat_a.messages.create!(role: "user", content: "Say exactly: done A", visible: true)
    chat_b.messages.create!(role: "user", content: "Say exactly: done B", visible: true)

    VCR.use_cassette("workspace_lock/sequential_chats") do
      LlmJob.perform_now(chat_a)

      chat_a.reload
      assert chat_a.completed?

      lock = WorkspaceLock.find_by(agent_name: "developer")
      assert_nil lock.holder_chat_id

      LlmJob.perform_now(chat_b)

      chat_b.reload
      assert chat_b.completed?
    end
  end
end
