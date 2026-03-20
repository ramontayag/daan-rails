# test/lib/daan/agent_registry_test.rb
require "test_helper"

class Daan::AgentRegistryTest < ActiveSupport::TestCase
  setup do
    @agent = Daan::Agent.new(name: "chief_of_staff", display_name: "CoS",
                             model_name: "m", system_prompt: "p", max_steps: 10)
  end

  test "registers and finds an agent by name" do
    Daan::AgentRegistry.register(@agent)
    assert_equal @agent, Daan::AgentRegistry.find("chief_of_staff")
  end

  test "all returns all registered agents" do
    Daan::AgentRegistry.register(@agent)
    assert_includes Daan::AgentRegistry.all, @agent
  end

  test "find raises AgentNotFoundError for unknown agent" do
    assert_raises(Daan::AgentNotFoundError) { Daan::AgentRegistry.find("nobody") }
  end

  test "clear removes all agents" do
    Daan::AgentRegistry.register(@agent)
    Daan::AgentRegistry.clear
    assert_raises(Daan::AgentNotFoundError) { Daan::AgentRegistry.find("chief_of_staff") }
  end
end
