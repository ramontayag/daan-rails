require "application_system_test_case"

class SidebarHighlightingTest < ApplicationSystemTestCase
  setup do
    Chat.destroy_all
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
    @agent = Daan::AgentRegistry.find("chief_of_staff")
  end

  test "agent is highlighted when viewing their thread" do
    # Create a chat for the agent
    chat = Chat.create!(agent_name: @agent.name)
    chat.messages.create!(role: "user", content: "Hello CoS!")

    # Visit the thread directly (simulating navigation via URL)
    visit chat_thread_path(chat)

    # Check that the agent is highlighted in the sidebar
    agent_item = find("[data-testid='agent-item']", text: "Chief of Staff")
    
    # The agent should have the active background class
    assert agent_item[:class].include?("bg-gray-800"), 
           "Expected agent to be highlighted with bg-gray-800 class, but found: #{agent_item[:class]}"
  end

  test "correct agent is highlighted when viewing different agents' threads" do
    # Create chats for different agents
    cos_chat = Chat.create!(agent_name: "chief_of_staff")
    cos_chat.messages.create!(role: "user", content: "Hello CoS!")
    
    em_chat = Chat.create!(agent_name: "engineering_manager") 
    em_chat.messages.create!(role: "user", content: "Hello EM!")

    # Visit CoS thread - CoS should be highlighted
    visit chat_thread_path(cos_chat)
    cos_item = find("[data-testid='agent-item']", text: "Chief of Staff")
    assert cos_item[:class].include?("bg-gray-800"), 
           "Chief of Staff should be highlighted when viewing their thread"

    # Visit EM thread - EM should be highlighted, CoS should not
    visit chat_thread_path(em_chat)
    em_item = find("[data-testid='agent-item']", text: "Engineering Manager")
    assert em_item[:class].include?("bg-gray-800"), 
           "Engineering Manager should be highlighted when viewing their thread"
    
    cos_item = find("[data-testid='agent-item']", text: "Chief of Staff")
    assert_not cos_item[:class].include?("bg-gray-800"), 
               "Chief of Staff should not be highlighted when viewing EM thread"
  end
end