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
    assert_equal 1, Daan::AgentRegistry.all.length
  end
end
