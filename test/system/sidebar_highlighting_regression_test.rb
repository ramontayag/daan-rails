require "application_system_test_case"

class SidebarHighlightingRegressionTest < ApplicationSystemTestCase
  test "agent is highlighted when directly navigating to thread URL" do
    # Create a chat and some messages to work with
    chat = Chat.create!(agent_name: "developer")
    Message.create!(chat: chat, role: "user", content: "Test message 1")
    Message.create!(chat: chat, role: "assistant", content: "Test response 1") 
    
    # Navigate directly to the thread URL (simulating user typing URL or refreshing page)
    visit "/chats/threads/#{chat.id}"
    
    # Debug: Check what we see on the page
    puts "\n=== DIRECT THREAD URL NAVIGATION TEST ==="
    puts "Current URL: #{current_url}"
    puts "Expected highlighted agent: developer"
    
    # Find the developer agent item in the sidebar
    developer_item = find("#agent_developer")
    
    # Check debug attributes if in development mode
    if Rails.env.development?
      puts "Debug attributes:"
      puts "  data-agent: #{developer_item['data-agent']}"
      puts "  data-active: #{developer_item['data-active']}"
      puts "  data-is-highlighted: #{developer_item['data-is-highlighted']}"
      puts "  data-current-agent: #{developer_item['data-current-agent']}"
    end
    
    # Get the link element inside the agent item
    developer_link = developer_item.find("a")
    link_classes = developer_link[:class].split
    
    puts "Developer link classes: #{link_classes.join(' ')}"
    puts "Contains bg-gray-800: #{link_classes.include?('bg-gray-800')}"
    
    # The critical assertion: developer should be highlighted
    assert link_classes.include?("bg-gray-800"), 
           "Developer agent should be highlighted when viewing its thread directly"
    
    # Additional verification: other agents should NOT be highlighted
    %w[engineering_manager chief_of_staff agent_resource_manager].each do |agent_name|
      if page.has_css?("#agent_#{agent_name}")
        other_agent = find("#agent_#{agent_name}")
        other_link = other_agent.find("a")
        other_classes = other_link[:class].split
        
        refute other_classes.include?("bg-gray-800"),
               "#{agent_name} should NOT be highlighted when viewing developer thread"
      end
    end
    
    puts "✅ SUCCESS: Agent highlighting works correctly for direct thread navigation"
  end
  
  test "agent highlighting works when switching between different threads" do
    # Create chats for different agents
    dev_chat = Chat.create!(agent_name: "developer")
    Message.create!(chat: dev_chat, role: "user", content: "Dev message")
    
    em_chat = Chat.create!(agent_name: "engineering_manager") 
    Message.create!(chat: em_chat, role: "user", content: "EM message")
    
    puts "\n=== THREAD SWITCHING TEST ==="
    
    # First, visit developer thread
    visit "/chats/threads/#{dev_chat.id}"
    
    developer_link = find("#agent_developer a")
    dev_classes = developer_link[:class].split
    assert dev_classes.include?("bg-gray-800"), 
           "Developer should be highlighted when viewing developer thread"
    
    # Now switch to engineering manager thread
    visit "/chats/threads/#{em_chat.id}"
    
    if page.has_css?("#agent_engineering_manager")
      em_link = find("#agent_engineering_manager a")
      em_classes = em_link[:class].split
      assert em_classes.include?("bg-gray-800"),
             "Engineering manager should be highlighted when viewing EM thread"
      
      # Developer should no longer be highlighted
      dev_link_after = find("#agent_developer a")
      dev_classes_after = dev_link_after[:class].split  
      refute dev_classes_after.include?("bg-gray-800"),
             "Developer should NOT be highlighted when viewing EM thread"
    else
      skip "Engineering manager agent not found in sidebar"
    end
    
    puts "✅ SUCCESS: Highlighting switches correctly between different agent threads"
  end
  
  test "reproduces exact user scenario - direct URL to specific thread" do
    # This test reproduces the exact scenario described by the user:
    # "when looking at a specific thread (/chats/threads/:id), the agent on the left-most bar is NOT highlighted"
    
    puts "\n=== EXACT USER SCENARIO REPRODUCTION ==="
    
    # Create a thread that user would typically navigate to directly
    chat = Chat.create!(agent_name: "developer")
    Message.create!(chat: chat, role: "user", content: "I have a bug to fix")
    Message.create!(chat: chat, role: "assistant", content: "I'll help you fix that bug")
    
    # Simulate user typing URL directly or refreshing page
    visit "/chats/threads/#{chat.id}"
    
    puts "Simulating user navigating directly to: /chats/threads/#{chat.id}"
    puts "Expected: developer agent should be highlighted in sidebar"
    puts "Current URL: #{current_url}"
    
    # Wait for page to fully load
    sleep 0.1
    
    # Check that we're on the correct page
    assert_text "I have a bug to fix"
    assert_text "I'll help you fix that bug"
    
    # The main assertion - check if developer is highlighted
    developer_item = find("#agent_developer")
    developer_link = developer_item.find("a")
    
    classes = developer_link[:class].split
    highlighted = classes.include?("bg-gray-800")
    
    puts "Developer agent classes: #{classes.join(' ')}"
    puts "Is highlighted (has bg-gray-800): #{highlighted}"
    
    # This is the critical test - if this fails, the bug is reproduced
    assert highlighted, 
           "REPRODUCTION CONFIRMED: Developer agent is NOT highlighted when viewing thread directly via URL. This is the bug the user reported."
    
    puts "✅ Agent highlighting works correctly - bug may have been fixed"
  end
end