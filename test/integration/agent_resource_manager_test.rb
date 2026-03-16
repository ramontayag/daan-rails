require "test_helper"

class AgentResourceManagerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    Chat.destroy_all
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
  end

  teardown do
    # Clean up any test agent files created during tests
    %w[test_created_agent test_integration_agent].each do |name|
      file = Rails.root.join("lib/daan/core/agents/#{name}.md")
      file.delete if file.exist?
    end

    Daan::AgentRegistry.clear
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
  end

  test "agent resource manager is loaded and available" do
    agent = Daan::AgentRegistry.find("agent_resource_manager")
    assert_equal "Agent Resource Manager", agent.display_name
    assert_includes agent.base_tools.map(&:name), "Daan::Core::CreateAgent"
    assert_includes agent.base_tools.map(&:name), "Daan::Core::EditAgent"
  end

  test "chief of staff can delegate to agent resource manager" do
    chief_of_staff = Daan::AgentRegistry.find("chief_of_staff")
    assert_includes chief_of_staff.delegates_to, "agent_resource_manager"
  end

  test "agent resource manager shows in sidebar" do
    get chat_path
    assert_response :success
    assert_select "[data-testid='agent-item']", text: /Agent Resource Manager/
  end

  test "can send message to agent resource manager" do
    agent = Daan::AgentRegistry.find("agent_resource_manager")

    assert_enqueued_with(job: LlmJob) do
      post chat_agent_threads_path(agent), params: {
        message: { content: "Create a new agent called test_agent" }
      }
    end

    assert_response :redirect
    chat = Chat.where(agent_name: "agent_resource_manager").last
    assert_equal 1, chat.messages.where(role: "user").count
    assert_equal "Create a new agent called test_agent", chat.messages.where(role: "user").first.content
  end

  test "delegation flow from chief of staff to agent resource manager" do
    chief_of_staff = Daan::AgentRegistry.find("chief_of_staff")

    # Send message to Chief of Staff about creating an agent
    assert_enqueued_with(job: LlmJob) do
      post chat_agent_threads_path(chief_of_staff), params: {
        message: { content: "Please create a new agent called 'task_manager' that helps manage tasks" }
      }
    end

    # Follow the redirect
    follow_redirect!
    assert_response :success

    # Verify chat was created
    chat = Chat.where(agent_name: "chief_of_staff").last
    assert chat.present?
    assert_equal 1, chat.messages.where(role: "user").count
  end

  test "agent resource manager tools are accessible" do
    agent = Daan::AgentRegistry.find("agent_resource_manager")
    chat = Chat.create!(agent_name: agent.name)

    # Test CreateAgent tool
    create_agent_tool = Daan::Core::CreateAgent.new(chat: chat)
    assert_respond_to create_agent_tool, :execute

    # Test EditAgent tool
    edit_agent_tool = Daan::Core::EditAgent.new(chat: chat)
    assert_respond_to edit_agent_tool, :execute
  end

  test "create agent tool basic functionality" do
    agent = Daan::AgentRegistry.find("agent_resource_manager")
    chat = Chat.create!(agent_name: agent.name)
    create_agent_tool = Daan::Core::CreateAgent.new(chat: chat)

    # This test uses a simplified version that doesn't fully create the file
    # to avoid filesystem side effects in integration tests
    result = create_agent_tool.execute(
      agent_name: "test_integration_agent",
      display_name: "Test Integration Agent",
      description: "An agent created during integration testing"
    )

    # Should at least validate the parameters without error
    # The actual file creation is tested in unit tests
    assert_includes result, "test_integration_agent"
  end

  test "edit agent tool basic functionality" do
    agent = Daan::AgentRegistry.find("agent_resource_manager")
    chat = Chat.create!(agent_name: agent.name)
    edit_agent_tool = Daan::Core::EditAgent.new(chat: chat)

    # Test editing a non-existent agent (should fail gracefully)
    result = edit_agent_tool.execute(
      agent_name: "nonexistent_agent",
      display_name: "Should Not Work"
    )

    assert_includes result, "Error"
    assert_includes result, "does not exist"
  end
end
