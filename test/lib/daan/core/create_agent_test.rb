require "test_helper"

class Daan::Core::CreateAgentTest < ActiveSupport::TestCase
  setup do
    @chat = Chat.create!(agent_name: "agent_resource_manager")
    @test_agents_dir = Pathname.new(Dir.mktmpdir("daan_create_agent_test"))

    # Create a developer agent file so delegate validation passes in tests that need it
    @test_agents_dir.join("developer.md").write("---\nname: developer\n---\nDeveloper agent")

    @tool = Daan::Core::CreateAgent.new(chat: @chat, agents_dir: @test_agents_dir)
  end

  teardown do
    FileUtils.rm_rf(@test_agents_dir) if @test_agents_dir.exist?
    Daan::AgentRegistry.clear
  end

  test "creates a basic agent with minimal parameters" do
    result = @tool.execute(
      agent_name: "test_agent",
      display_name: "Test Agent",
      description: "A test agent for unit testing"
    )

    assert_includes result, "Successfully created agent 'test_agent'"

    agent_file = @test_agents_dir.join("test_agent.md")
    assert agent_file.exist?

    content = agent_file.read
    assert_includes content, "name: test_agent"
    assert_includes content, "display_name: Test Agent"
    assert_includes content, "model: claude-sonnet-4-20250514"
    assert_includes content, "max_turns: 10"
    assert_includes content, "A test agent for unit testing"
  end

  test "creates agent with all optional parameters" do
    result = @tool.execute(
      agent_name: "full_agent",
      display_name: "Full Agent",
      description: "A fully configured agent",
      tools: ["Daan::Core::Read", "Daan::Core::Write"],
      delegates_to: ["developer"],
      workspace: "tmp/workspaces/full_agent",
      model: "claude-haiku",
      max_turns: 5
    )

    assert_includes result, "Successfully created agent 'full_agent'"

    content = @test_agents_dir.join("full_agent.md").read
    assert_includes content, "workspace: tmp/workspaces/full_agent"
    assert_includes content, "model: claude-haiku"
    assert_includes content, "max_turns: 5"
    assert_includes content, "- Daan::Core::Read"
    assert_includes content, "- Daan::Core::Write"
    assert_includes content, "- developer"
  end

  test "rejects invalid agent names" do
    result = @tool.execute(
      agent_name: "Invalid-Name",
      display_name: "Invalid Agent",
      description: "Should fail"
    )

    assert_includes result, "Error: agent_name must start with a lowercase letter"
  end

  test "rejects duplicate agent names" do
    @test_agents_dir.join("existing_agent.md").write("---\nname: existing_agent\n---\nExisting agent")

    result = @tool.execute(
      agent_name: "existing_agent",
      display_name: "Existing Agent",
      description: "Should fail"
    )

    assert_includes result, "Error: Agent 'existing_agent' already exists"
  end

  test "validates tool class existence" do
    result = @tool.execute(
      agent_name: "test_agent",
      display_name: "Test Agent",
      description: "Test with invalid tool",
      tools: ["NonExistentTool"]
    )

    assert_includes result, "Error: Tool class 'NonExistentTool' does not exist"
  end

  test "validates delegate agent existence" do
    result = @tool.execute(
      agent_name: "test_agent",
      display_name: "Test Agent",
      description: "Test with invalid delegate",
      delegates_to: ["non_existent_agent"]
    )

    assert_includes result, "Error: Delegate agent 'non_existent_agent' does not exist"
  end

  test "registers agent in registry after creation" do
    real_agents_dir = Rails.root.join("lib/daan/core/agents")
    tool = Daan::Core::CreateAgent.new(chat: @chat, agents_dir: real_agents_dir)

    result = tool.execute(
      agent_name: "registry_test",
      display_name: "Registry Test",
      description: "Testing registry integration"
    )

    assert_includes result, "Successfully created agent 'registry_test'"
    assert_equal "Registry Test", Daan::AgentRegistry.find("registry_test").display_name
  ensure
    real_agents_dir.join("registry_test.md").delete rescue nil
  end

  test "handles empty arrays correctly" do
    result = @tool.execute(
      agent_name: "empty_arrays_agent",
      display_name: "Empty Arrays Agent",
      description: "Agent with empty tool/delegate arrays",
      tools: [],
      delegates_to: []
    )

    assert_includes result, "Successfully created agent 'empty_arrays_agent'"

    content = @test_agents_dir.join("empty_arrays_agent.md").read
    refute_includes content, "tools:"
    refute_includes content, "delegates_to:"
  end
end
