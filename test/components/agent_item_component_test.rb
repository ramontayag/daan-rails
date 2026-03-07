require "test_helper"

class AgentItemComponentTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  def idle_agent
    Daan::AgentRegistry.register(
      Daan::Agent.new(name: "chief_of_staff", display_name: "Chief of Staff",
                      model_name: "claude-3-5-haiku-20241022", system_prompt: "p", max_turns: 10)
    )
    Daan::AgentRegistry.find("chief_of_staff")
  end

  test "idle agent shows green dot" do
    agent = idle_agent
    agent.define_singleton_method(:busy?) { false }
    render_inline(AgentItemComponent.new(agent: agent))
    assert_includes rendered_content, "data-testid=\"agent-item\""
    assert_includes rendered_content, "id=\"agent_chief_of_staff\""
    assert_includes rendered_content, "Chief of Staff"
    assert_includes rendered_content, "bg-green-400"
  end

  test "busy agent shows yellow dot" do
    agent = idle_agent
    agent.define_singleton_method(:busy?) { true }
    render_inline(AgentItemComponent.new(agent: agent))
    assert_includes rendered_content, "bg-yellow-400"
  end

  test "active agent has highlighted background" do
    agent = idle_agent
    agent.define_singleton_method(:busy?) { false }
    render_inline(AgentItemComponent.new(agent: agent, active: true))
    # "hover:bg-gray-800 bg-gray-800" appears only in active branch; inactive has just hover:bg-gray-800
    assert_includes rendered_content, "hover:bg-gray-800 bg-gray-800"
  end

  test "inactive agent does not have active background class" do
    agent = idle_agent
    agent.define_singleton_method(:busy?) { false }
    render_inline(AgentItemComponent.new(agent: agent, active: false))
    assert_not_includes rendered_content, "hover:bg-gray-800 bg-gray-800"
  end
end
