# test/controllers/threads_controller_test.rb
require "test_helper"

class ThreadsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    Daan::Core::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
    @agent = Daan::Core::AgentRegistry.find("chief_of_staff")
  end

  test "GET shows thread panel with messages" do
    chat = Chat.create!(agent_name: "chief_of_staff")
    chat.messages.create!(role: "user", content: "Hello")
    get chat_thread_path(chat)
    assert_response :success
    assert_select "[data-testid='thread-panel']"
    assert_select "[data-testid='message']", minimum: 1
  end

  test "POST always creates a new chat" do
    Chat.create!(agent_name: "chief_of_staff")
    assert_difference "Chat.count", 1 do
      post chat_agent_threads_path(@agent),
           params: { message: { content: "New task" } }
    end
    assert_response :redirect
  end

  test "POST creates user message and enqueues LlmJob" do
    assert_enqueued_with(job: LlmJob) do
      post chat_agent_threads_path(@agent),
           params: { message: { content: "Hello CoS" } }
    end
    assert_equal "user", Message.last.role
    assert_equal "Hello CoS", Message.last.content
  end

  test "GET /threads/:id with perspective param is successful" do
    em_chat = Chat.create!(agent_name: "engineering_manager")
    sub_chat = Chat.create!(agent_name: "chief_of_staff", parent_chat_id: em_chat.id)
    get chat_thread_path(sub_chat), params: { perspective: "engineering_manager" }
    assert_response :success
  end

  test "show_tasks param is preserved in response when true" do
    chat = Chat.create!(agent_name: "chief_of_staff")
    ChatStep.create!(chat: chat, title: "Do something", position: 1)

    get chat_thread_path(chat, show_tasks: "1")

    assert_response :success
    assert_select "#chat_step_panel:not(.hidden)"
  end

  test "step panel is hidden by default (no show_tasks param)" do
    chat = Chat.create!(agent_name: "chief_of_staff")
    ChatStep.create!(chat: chat, title: "Do something", position: 1)

    get chat_thread_path(chat)

    assert_response :success
    assert_select "#chat_step_panel.hidden"
  end
end
