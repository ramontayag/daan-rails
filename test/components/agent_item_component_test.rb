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

  def other_agent
    Daan::AgentRegistry.register(
      Daan::Agent.new(name: "developer", display_name: "Developer",
                      model_name: "claude-3-5-haiku-20241022", system_prompt: "p", max_turns: 10)
    )
    Daan::AgentRegistry.find("developer")
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

  test "agent is highlighted when current_agent matches by name (fallback logic)" do
    agent = idle_agent
    current_agent = other_agent
    # Simulate different objects with same name
    current_agent.define_singleton_method(:name) { "chief_of_staff" }
    
    render_inline(AgentItemComponent.new(agent: agent, active: false, current_agent: current_agent))
    assert_includes rendered_content, "hover:bg-gray-800 bg-gray-800"
  end

  test "agent is not highlighted when current_agent has different name" do
    agent = idle_agent
    current_agent = other_agent
    
    render_inline(AgentItemComponent.new(agent: agent, active: false, current_agent: current_agent))
    assert_not_includes rendered_content, "hover:bg-gray-800 bg-gray-800"
  end

  test "active flag takes precedence over current_agent fallback" do
    agent = idle_agent
    current_agent = other_agent  # Different agent
    
    render_inline(AgentItemComponent.new(agent: agent, active: true, current_agent: current_agent))
    assert_includes rendered_content, "hover:bg-gray-800 bg-gray-800"
  end

  test "debug attributes are present in development mode" do
    with_rails_env("development") do
      agent = idle_agent
      current_agent = other_agent
      
      render_inline(AgentItemComponent.new(agent: agent, active: false, current_agent: current_agent))
      assert_includes rendered_content, "data-agent-name=\"chief_of_staff\""
      assert_includes rendered_content, "data-current-agent-name=\"developer\""
      assert_includes rendered_content, "data-is-active=\"false\""
    end
  end

  test "debug attributes are not present in production mode" do
    with_rails_env("production") do
      agent = idle_agent
      current_agent = other_agent
      
      render_inline(AgentItemComponent.new(agent: agent, active: false, current_agent: current_agent))
      assert_not_includes rendered_content, "data-agent-name"
      assert_not_includes rendered_content, "data-current-agent-name"
    end
  end

  private

  def with_rails_env(env)
    original_env = Rails.env
    Rails.instance_variable_set(:@_env, ActiveSupport::StringInquirer.new(env))
    yield
  ensure
    Rails.instance_variable_set(:@_env, ActiveSupport::StringInquirer.new(original_env))
  end
end