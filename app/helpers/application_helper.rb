module ApplicationHelper
  def agent_display_name(agent_name)
    Daan::Core::AgentRegistry.find(agent_name).display_name
  rescue Daan::Core::AgentNotFoundError
    agent_name
  end
end
