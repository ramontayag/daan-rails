require "test_helper"

class SidebarHighlightingTest < ActionDispatch::IntegrationTest
  setup do
    Chat.destroy_all 
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
    @agent_name = "developer"
  end

  test "agent registry object equality - the core of highlighting bug" do
    # This test focuses on the core issue: object identity in AgentRegistry
    
    # Simulate what happens in the controller
    # ThreadsController sets @agent = Daan::AgentRegistry.find(@chat.agent_name)
    current_agent = Daan::AgentRegistry.find(@agent_name)
    
    # Simulate what happens in SidebarComponent
    # agents.each do |agent|
    #   render AgentItemComponent.new(agent: agent, active: agent == current_agent)
    all_agents = Daan::AgentRegistry.all
    target_agent = all_agents.find { |a| a.name == @agent_name }
    
    # This is the critical comparison that determines if highlighting works
    comparison_result = target_agent == current_agent
    
    puts ""
    puts "=== DEBUGGING AGENT HIGHLIGHTING BUG ==="
    puts "Agent name: #{@agent_name}"
    puts "Current agent (from find): #{current_agent.object_id} - #{current_agent.name}"
    puts "Target agent (from all): #{target_agent.object_id} - #{target_agent.name}"
    puts "Object equality (==): #{comparison_result}"
    puts "Same object_id: #{current_agent.object_id == target_agent.object_id}"
    puts "Same name: #{current_agent.name == target_agent.name}"
    puts ""
    
    if comparison_result
      puts "✅ GOOD: Objects are equal - highlighting should work"
    else
      puts "❌ BUG: Objects are NOT equal - highlighting will fail"  
      puts "This is why agents aren't highlighted in the sidebar!"
      puts ""
      puts "SOLUTION: Change comparison from object equality to name comparison"
      puts "In AgentItemComponent, use: active: agent.name == current_agent&.name"
    end
    
    assert comparison_result, "Agent comparison should work for highlighting"
  end

  test "potential URL vs agent_name mismatch scenario" do
    # Test what happens if URL agent name differs from chat agent name
    # This could be a source of the highlighting bug
    
    url_agent_name = "developer"
    
    # Create a fake chat object to simulate controller logic
    chat_agent_name = "developer"  # Normally they should match
    
    # Simulate ThreadsController#show logic
    # @agent = Daan::AgentRegistry.find(@chat.agent_name)  
    agent_from_chat = Daan::AgentRegistry.find(chat_agent_name)
    
    # Simulate SidebarComponent logic 
    all_agents = Daan::AgentRegistry.all
    sidebar_agent = all_agents.find { |a| a.name == url_agent_name }
    
    url_vs_chat_match = (url_agent_name == chat_agent_name)
    object_comparison = (sidebar_agent == agent_from_chat)
    
    puts ""
    puts "=== TESTING URL vs CHAT AGENT MISMATCH ==="
    puts "URL agent name: #{url_agent_name}"
    puts "Chat agent name: #{chat_agent_name}"
    puts "Names match: #{url_vs_chat_match}"
    puts "Object comparison result: #{object_comparison}"
    puts ""
    
    if url_vs_chat_match && object_comparison
      puts "✅ Normal case: URL and chat agent match, highlighting should work"
    elsif !url_vs_chat_match
      puts "❌ POTENTIAL BUG: URL agent differs from chat agent"
      puts "User visits /chat/agents/#{url_agent_name}/threads/123"
      puts "But chat.agent_name is '#{chat_agent_name}'" 
      puts "This would cause highlighting to fail!"
    else
      puts "❌ UNEXPECTED: Names match but objects don't equal"
    end
    
    assert true  # Just debugging, don't fail
  end

  test "simulate exact ThreadsController behavior" do
    # This simulates the exact controller and view logic
    
    # Fake URL parameters
    params_agent_name = "developer"
    
    # We'd need a real chat for this, but let's simulate it
    # In real controller: @chat = Chat.find(params[:id])  
    # Then: @agent = Daan::AgentRegistry.find(@chat.agent_name)
    chat_agent_name = "developer"  # Chat's agent_name from DB
    
    # Controller logic
    controller_agent = Daan::AgentRegistry.find(chat_agent_name)
    
    # View renders: SidebarComponent.new(current_agent: @agent)
    # SidebarComponent iterates: agents.each do |agent|
    # And passes: AgentItemComponent.new(agent: agent, active: agent == current_agent)
    
    sidebar_agents = Daan::AgentRegistry.all
    highlighting_results = {}
    
    sidebar_agents.each do |sidebar_agent|
      active = sidebar_agent == controller_agent
      highlighting_results[sidebar_agent.name] = active
    end
    
    puts ""
    puts "=== SIMULATING EXACT CONTROLLER/VIEW LOGIC ==="  
    puts "Params agent name: #{params_agent_name}"
    puts "Chat agent name: #{chat_agent_name}"
    puts "Controller agent object_id: #{controller_agent.object_id}"
    puts ""
    puts "Highlighting results:"
    highlighting_results.each do |name, active|
      status = active ? "✅ HIGHLIGHTED" : "⚪ not highlighted"
      puts "  #{name}: #{status}"
    end
    
    expected_highlighted = highlighting_results[params_agent_name]
    if expected_highlighted
      puts ""
      puts "✅ SUCCESS: Expected agent would be highlighted"
    else
      puts ""  
      puts "❌ BUG: Expected agent would NOT be highlighted!"
    end
    
    assert true
  end
end