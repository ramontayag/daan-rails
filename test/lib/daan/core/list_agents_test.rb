# test/lib/daan/core/list_agents_test.rb
require "test_helper"

class Daan::Core::ListAgentsTest < ActiveSupport::TestCase
  test "returns formatted list of all registered agents" do
    agent = Daan::Core::Agent.new(
      name: "developer",
      display_name: "Developer",
      base_tools: [ Daan::Core::Read ]
    )
    Daan::Core::AgentRegistry.register(agent)

    tool = Daan::Core::ListAgents.new
    result = tool.execute

    assert_includes result, "Developer (developer)"
    assert_includes result, "Daan::Core::Read"
  end

  test "returns message when no agents registered" do
    tool = Daan::Core::ListAgents.new
    result = tool.execute
    assert_includes result, "No agents"
  end
end
