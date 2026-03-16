require "test_helper"

class SidebarHighlightingImprovementTest < ViewComponent::TestCase
  def test_enhanced_agent_item_component_with_fallback_highlighting
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
    agent = Daan::AgentRegistry.find("developer")
    current_agent = Daan::AgentRegistry.find("developer")
    
    # Test primary highlighting method (active: true)
    render_inline(AgentItemComponent.new(agent: agent, active: true, current_agent: current_agent))
    assert_selector("a.bg-gray-800")
    
    # Test fallback highlighting method (active: false, but current_agent matches)
    render_inline(AgentItemComponent.new(agent: agent, active: false, current_agent: current_agent))
    assert_selector("a.bg-gray-800")  # Should still highlight due to fallback
    
    # Test no highlighting (active: false, different current_agent)
    other_agent = Daan::AgentRegistry.find("chief_of_staff") 
    render_inline(AgentItemComponent.new(agent: agent, active: false, current_agent: other_agent))
    assert_no_selector("a.bg-gray-800")
  end
  
  def test_debug_attributes_in_development_environment
    skip unless Rails.env.development?
    
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
    agent = Daan::AgentRegistry.find("developer")
    current_agent = Daan::AgentRegistry.find("developer")
    
    render_inline(AgentItemComponent.new(agent: agent, active: true, current_agent: current_agent))
    
    # Should have debug data attributes
    assert_selector("div[data-agent='developer']")
    assert_selector("div[data-active='true']")  
    assert_selector("div[data-is-highlighted='true']")
    assert_selector("div[data-current-agent='developer']")
  end
  
  def test_maintains_backward_compatibility
    # Test that existing usage (without current_agent parameter) still works
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
    agent = Daan::AgentRegistry.find("developer")
    
    # Old way: just agent and active parameters
    render_inline(AgentItemComponent.new(agent: agent, active: true))
    assert_selector("a.bg-gray-800")
    
    render_inline(AgentItemComponent.new(agent: agent, active: false))
    assert_no_selector("a.bg-gray-800")
  end
end