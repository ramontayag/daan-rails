# test/lib/daan/agent_registry_test.rb
require "test_helper"

class Daan::Core::AgentRegistryTest < ActiveSupport::TestCase
  setup do
    @agent = build_agent(name: "chief_of_staff")
  end

  test "registers and finds an agent by name" do
    Daan::Core::AgentRegistry.register(@agent)
    assert_equal @agent, Daan::Core::AgentRegistry.find("chief_of_staff")
  end

  test "all returns all registered agents" do
    Daan::Core::AgentRegistry.register(@agent)
    assert_includes Daan::Core::AgentRegistry.all, @agent
  end

  test "find raises AgentNotFoundError for unknown agent" do
    assert_raises(Daan::Core::AgentNotFoundError) { Daan::Core::AgentRegistry.find("nobody") }
  end

  test "clear removes all agents" do
    Daan::Core::AgentRegistry.register(@agent)
    Daan::Core::AgentRegistry.clear
    assert_raises(Daan::Core::AgentNotFoundError) { Daan::Core::AgentRegistry.find("chief_of_staff") }
  end
end
