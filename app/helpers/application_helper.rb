module ApplicationHelper
  def agent_display_name(agent_name)
    Daan::AgentRegistry.find(agent_name).display_name
  rescue Daan::AgentNotFoundError
    agent_name
  end
end
