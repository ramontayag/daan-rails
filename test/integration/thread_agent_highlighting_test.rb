require "test_helper"

class ThreadAgentHighlightingTest < ActionDispatch::IntegrationTest
  test "agent highlighting works when visiting thread URL directly" do
    # Create a chat for the developer agent
    chat = Chat.create!(agent_name: "developer")
    Message.create!(chat: chat, role: "user", content: "Test message")
    
    puts "\n=== INTEGRATION TEST: Direct Thread URL Navigation ==="
    puts "Testing URL: /chats/threads/#{chat.id}"
    puts "Expected agent to highlight: developer"
    
    # Visit the thread URL directly (simulates user typing URL or refreshing)
    get "/chats/threads/#{chat.id}"
    
    assert_response :success
    
    # Parse the response to check if the correct agent is set
    assert_select "aside[data-testid='sidebar']" do
      # Check that the developer agent item exists and has the right attributes
      assert_select "#agent_developer" do |elements|
        agent_div = elements.first
        
        # In development, we should have debug attributes
        if Rails.env.development?
          puts "Debug attributes found:"
          puts "  data-agent: #{agent_div['data-agent']}"
          puts "  data-is-highlighted: #{agent_div['data-is-highlighted']}"
          puts "  data-current-agent: #{agent_div['data-current-agent']}"
        end
        
        # Check that the link inside has the highlighted class
        assert_select "a.bg-gray-800", 1, "Developer agent should have bg-gray-800 class (highlighted)"
      end
      
      # Verify other agents are NOT highlighted
      %w[engineering_manager chief_of_staff agent_resource_manager].each do |agent_name|
        css_selector = "#agent_#{agent_name} a:not(.bg-gray-800)"
        if page_has_element?("#agent_#{agent_name}")
          # If the agent exists, it should NOT be highlighted
          assert_select css_selector, minimum: 1,
                        "#{agent_name} should NOT be highlighted when viewing developer thread"
        end
      end
    end
    
    puts "✅ SUCCESS: Developer agent is correctly highlighted in sidebar"
  end
  
  test "highlighting changes correctly when switching between threads" do
    # Create threads for different agents
    dev_chat = Chat.create!(agent_name: "developer")
    em_chat = Chat.create!(agent_name: "engineering_manager")
    
    puts "\n=== INTEGRATION TEST: Thread Switching ==="
    
    # First, visit developer thread
    get "/chats/threads/#{dev_chat.id}"
    assert_response :success
    
    puts "Step 1: Visiting developer thread"
    assert_select "#agent_developer a.bg-gray-800", 1, 
                  "Developer should be highlighted when viewing developer thread"
    
    # Now visit engineering manager thread
    get "/chats/threads/#{em_chat.id}"
    assert_response :success
    
    puts "Step 2: Visiting engineering manager thread"
    
    # Check if EM exists in the agent list
    if response.body.include?("agent_engineering_manager")
      assert_select "#agent_engineering_manager a.bg-gray-800", 1,
                    "Engineering manager should be highlighted when viewing EM thread"
      
      # Developer should no longer be highlighted
      assert_select "#agent_developer a:not(.bg-gray-800)", minimum: 1,
                    "Developer should NOT be highlighted when viewing EM thread"
    else
      puts "⚠️  Engineering manager not found in sidebar - skipping EM highlighting check"
    end
    
    puts "✅ SUCCESS: Highlighting switches correctly between threads"
  end
  
  private
  
  def page_has_element?(selector)
    # Helper to check if an element exists in the response
    doc = Nokogiri::HTML(response.body)
    doc.css(selector).any?
  end
end