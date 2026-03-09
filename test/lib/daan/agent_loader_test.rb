# test/lib/daan/agent_loader_test.rb
require "test_helper"

class Daan::AgentLoaderTest < ActiveSupport::TestCase
  setup do
    @definitions_path = Rails.root.join("lib/daan/core/agents")
  end

  test "parse returns a hash with agent attributes" do
    definition = Daan::AgentLoader.parse(@definitions_path.join("chief_of_staff.md"))

    assert_equal "chief_of_staff", definition[:name]
    assert_equal "Chief of Staff", definition[:display_name]
    assert_equal "claude-sonnet-4-20250514", definition[:model_name]
    assert_equal 10, definition[:max_turns]
    assert definition[:system_prompt].start_with?("You are the Chief of Staff")
  end

  test "sync! registers a Daan::Agent for each definition file" do
    Daan::AgentLoader.sync!(@definitions_path)

    agent = Daan::AgentRegistry.find("chief_of_staff")
    assert_instance_of Daan::Agent, agent
    assert_equal "Chief of Staff", agent.display_name
    assert_equal "claude-sonnet-4-20250514", agent.model_name
  end

  test "sync! re-running overwrites previous registration" do
    Daan::AgentLoader.sync!(@definitions_path)
    Daan::AgentLoader.sync!(@definitions_path)
    assert_equal 3, Daan::AgentRegistry.all.length
  end

  test "parse returns base_tools array for chief_of_staff agent" do
    definition = Daan::AgentLoader.parse(@definitions_path.join("chief_of_staff.md"))
    assert_includes definition[:base_tools], Daan::Core::DelegateTask
  end

  test "parse returns nil workspace when not in frontmatter" do
    definition = Daan::AgentLoader.parse(@definitions_path.join("chief_of_staff.md"))
    assert_nil definition[:workspace]
  end

  test "parse returns base_tools array for developer agent" do
    definition = Daan::AgentLoader.parse(@definitions_path.join("developer.md"))
    assert_includes definition[:base_tools], Daan::Core::Read
    assert_includes definition[:base_tools], Daan::Core::Write
  end

  test "parse returns workspace for developer agent" do
    definition = Daan::AgentLoader.parse(@definitions_path.join("developer.md"))
    assert definition[:workspace].to_s.end_with?("tmp/workspaces/developer")
  end

  test "sync! registers developer agent with workspace-bound tools" do
    Daan::AgentLoader.sync!(@definitions_path)
    agent = Daan::AgentRegistry.find("developer")
    assert_not_nil agent.workspace
    assert agent.tools.all? { |t| t.is_a?(RubyLLM::Tool) }
  end

  test "parse returns empty delegates_to when not in frontmatter" do
    definition = Daan::AgentLoader.parse(@definitions_path.join("developer.md"))
    assert_equal [], definition[:delegates_to]
  end

  test "loads engineering_manager with delegates_to developer" do
    Daan::AgentLoader.sync!(@definitions_path)
    agent = Daan::AgentRegistry.find("engineering_manager")
    assert_not_nil agent
    assert_equal ["developer"], agent.delegates_to
    assert agent.base_tools.include?(Daan::Core::DelegateTask)
    assert agent.base_tools.include?(Daan::Core::ReportBack)
  end

  test "chief_of_staff has DelegateTask and delegates_to engineering_manager" do
    Daan::AgentLoader.sync!(@definitions_path)
    agent = Daan::AgentRegistry.find("chief_of_staff")
    assert_equal ["engineering_manager"], agent.delegates_to
    assert agent.base_tools.include?(Daan::Core::DelegateTask)
  end

  test "developer has ReportBack tool" do
    Daan::AgentLoader.sync!(@definitions_path)
    agent = Daan::AgentRegistry.find("developer")
    assert agent.base_tools.include?(Daan::Core::ReportBack)
  end
end
