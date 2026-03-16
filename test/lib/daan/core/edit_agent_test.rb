require "test_helper"

class Daan::Core::EditAgentTest < ActiveSupport::TestCase
  setup do
    @chat = Chat.create!(agent_name: "agent_resource_manager")
    @test_agents_dir = Pathname.new(Dir.mktmpdir("daan_edit_agent_test"))

    @agent_file = @test_agents_dir.join("test_agent.md")
    @agent_file.write(<<~AGENT)
      ---
      name: test_agent
      display_name: Test Agent
      model: claude-sonnet-4-20250514
      max_turns: 10
      workspace: tmp/workspaces/test_agent
      tools:
        - Daan::Core::Read
        - Daan::Core::Write
      delegates_to:
        - developer
      ---
      This is a test agent for editing.
    AGENT

    @test_agents_dir.join("developer.md").write("---\nname: developer\n---\nDeveloper agent")

    @tool = Daan::Core::EditAgent.new(chat: @chat, agents_dir: @test_agents_dir)
  end

  teardown do
    FileUtils.rm_rf(@test_agents_dir) if @test_agents_dir&.exist?
    Daan::AgentRegistry.clear
  end

  test "returns error for nonexistent agent" do
    result = @tool.execute(agent_name: "nonexistent_agent")

    assert_includes result, "Error: Agent 'nonexistent_agent' does not exist"
  end

  test "updates display name" do
    result = @tool.execute(agent_name: "test_agent", display_name: "Updated Test Agent")

    assert_includes result, "Successfully updated agent 'test_agent'"
    assert_includes result, "display_name"

    content = @agent_file.read
    assert_includes content, "display_name: Updated Test Agent"
    refute_includes content, "display_name: Test Agent"
  end

  test "updates description" do
    result = @tool.execute(agent_name: "test_agent", description: "This is an updated description.")

    assert_includes result, "Successfully updated agent 'test_agent'"
    assert_includes result, "description"

    content = @agent_file.read
    assert_includes content, "This is an updated description."
    refute_includes content, "This is a test agent for editing."
  end

  test "updates tools array" do
    result = @tool.execute(agent_name: "test_agent", tools: [ "Daan::Core::Read", "Daan::Core::ReportBack" ])

    assert_includes result, "Successfully updated agent 'test_agent'"
    assert_includes result, "tools"

    content = @agent_file.read
    assert_includes content, "- Daan::Core::ReportBack"
    refute_includes content, "- Daan::Core::Write"
  end

  test "removes tools when empty array provided" do
    result = @tool.execute(agent_name: "test_agent", tools: [])

    assert_includes result, "Successfully updated agent 'test_agent'"

    content = @agent_file.read
    refute_includes content, "tools:"
    refute_includes content, "- Daan::Core::Read"
  end

  test "updates delegates_to array" do
    result = @tool.execute(agent_name: "test_agent", delegates_to: [ "developer" ])

    assert_includes result, "Successfully updated agent 'test_agent'"
    assert_includes result, "delegates_to"

    content = @agent_file.read
    assert_includes content, "- developer"
  end

  test "removes delegates_to when empty array provided" do
    result = @tool.execute(agent_name: "test_agent", delegates_to: [])

    assert_includes result, "Successfully updated agent 'test_agent'"

    content = @agent_file.read
    refute_includes content, "delegates_to:"
  end

  test "removes workspace when empty string provided" do
    result = @tool.execute(agent_name: "test_agent", workspace: "")

    assert_includes result, "Successfully updated agent 'test_agent'"

    content = @agent_file.read
    refute_includes content, "workspace:"
  end

  test "updates workspace path" do
    result = @tool.execute(agent_name: "test_agent", workspace: "tmp/workspaces/updated_agent")

    assert_includes result, "Successfully updated agent 'test_agent'"

    content = @agent_file.read
    assert_includes content, "workspace: tmp/workspaces/updated_agent"
  end

  test "updates model and max_turns" do
    result = @tool.execute(agent_name: "test_agent", model: "claude-haiku", max_turns: 5)

    assert_includes result, "Successfully updated agent 'test_agent'"
    assert_includes result, "model"
    assert_includes result, "max_turns"

    content = @agent_file.read
    assert_includes content, "model: claude-haiku"
    assert_includes content, "max_turns: 5"
  end

  test "validates tool class existence" do
    result = @tool.execute(agent_name: "test_agent", tools: [ "NonExistentTool" ])

    assert_includes result, "Error: Tool class 'NonExistentTool' does not exist"

    content = @agent_file.read
    assert_includes content, "- Daan::Core::Read"
    refute_includes content, "NonExistentTool"
  end

  test "validates delegate agent existence" do
    result = @tool.execute(agent_name: "test_agent", delegates_to: [ "nonexistent_delegate" ])

    assert_includes result, "Error: Delegate agent 'nonexistent_delegate' does not exist"

    content = @agent_file.read
    assert_includes content, "- developer"
    refute_includes content, "nonexistent_delegate"
  end

  test "preserves existing values when not updated" do
    result = @tool.execute(agent_name: "test_agent", display_name: "Updated Name Only")

    assert_includes result, "Successfully updated agent 'test_agent'"

    content = @agent_file.read
    assert_includes content, "display_name: Updated Name Only"
    assert_includes content, "model: claude-sonnet-4-20250514"
    assert_includes content, "max_turns: 10"
    assert_includes content, "workspace: tmp/workspaces/test_agent"
    assert_includes content, "- Daan::Core::Read"
    assert_includes content, "- developer"
    assert_includes content, "This is a test agent for editing."
  end

  test "updates multiple fields at once" do
    result = @tool.execute(
      agent_name: "test_agent",
      display_name: "Multi Update Agent",
      description: "Updated with multiple changes",
      model: "claude-haiku",
      tools: [ "Daan::Core::ReportBack" ]
    )

    assert_includes result, "Successfully updated agent 'test_agent'"
    assert_includes result, "display_name, description, tools, model"

    content = @agent_file.read
    assert_includes content, "display_name: Multi Update Agent"
    assert_includes content, "model: claude-haiku"
    assert_includes content, "- Daan::Core::ReportBack"
    assert_includes content, "Updated with multiple changes"
    refute_includes content, "- Daan::Core::Read"
  end

  test "handles malformed agent file" do
    @agent_file.write("invalid yaml content")

    result = @tool.execute(agent_name: "test_agent", display_name: "Should Fail")

    assert_includes result, "Error: Failed to parse existing agent file"
  end

  test "registers updated agent in registry" do
    real_agents_dir = Rails.root.join("lib/daan/core/agents")
    real_agent_file = real_agents_dir.join("registry_edit_test.md")
    real_agent_file.write(<<~AGENT)
      ---
      name: registry_edit_test
      display_name: Registry Edit Test
      model: claude-sonnet-4-20250514
      max_turns: 10
      ---
      Test agent for registry editing
    AGENT

    tool = Daan::Core::EditAgent.new(chat: @chat, agents_dir: real_agents_dir)
    result = tool.execute(agent_name: "registry_edit_test", display_name: "Updated Registry Test")

    assert_includes result, "Successfully updated agent 'registry_edit_test'"
    assert_equal "Updated Registry Test", Daan::AgentRegistry.find("registry_edit_test").display_name
  ensure
    real_agent_file.delete rescue nil
  end
end
