module SidebarAgents
  extend ActiveSupport::Concern

  included do
    rescue_from Daan::AgentNotFoundError, with: :agent_not_found
  end

  private

  def set_agents
    @agents = Daan::AgentRegistry.all
  end

  def agent_not_found
    head :not_found
  end
end
