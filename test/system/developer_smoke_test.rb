require "test_helper"

# Smoke test: Developer agent writes a file, user sees the reply in the thread
# panel, then asks to read the file back — all from within the same thread.
class DeveloperSmokeTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    Chat.destroy_all
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
    @workspace = Rails.root.join("tmp", "workspaces", "developer")
    FileUtils.mkdir_p(@workspace)
  end

  teardown do
    FileUtils.rm_f(@workspace.join("smoke_test.txt"))
  end

  test "developer writes a file and reads it back through the thread panel" do
    agent = Daan::AgentRegistry.find("developer")

    # Turn 1: create thread and write the file
    VCR.use_cassette("developer_smoke/write_turn") do
      perform_enqueued_jobs do
        post chat_agent_threads_path(agent),
             params: { message: { content: 'Write "hello from smoke test" to smoke_test.txt' } }
      end
    end

    assert_response :redirect
    chat = Chat.where(agent_name: "developer").last
    assert chat.completed?, "expected chat to be completed after write turn"
    assert File.exist?(@workspace.join("smoke_test.txt")), "expected file to exist"
    assert_equal "hello from smoke test", File.read(@workspace.join("smoke_test.txt")).strip

    # Follow redirect to thread panel — write tool call is visible
    follow_redirect!
    assert_response :success
    assert_select "[data-testid='thread-panel']"
    assert_select "[data-testid='tool-call']", minimum: 1

    # Turn 2: reply in the same thread asking for the file to be read back
    VCR.use_cassette("developer_smoke/read_turn") do
      perform_enqueued_jobs do
        post chat_thread_messages_path(chat),
             params: { message: { content: "Now read smoke_test.txt back to me" } }
      end
    end

    assert_response :redirect
    chat.reload
    assert chat.completed?, "expected chat to be completed after read turn"

    # Follow redirect to thread panel — read tool call shows file contents
    follow_redirect!
    assert_response :success
    assert_select "[data-testid='tool-call']", minimum: 2
    assert_includes response.body, "hello from smoke test"
  end
end
