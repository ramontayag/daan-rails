module SidebarAgents
  extend ActiveSupport::Concern

  included do
    rescue_from Daan::AgentNotFoundError, with: :agent_not_found
  end

  private

  def set_agents
    all = Daan::AgentRegistry.all
    @agents = if @perspective_agent
      partner_names = Chat.conversation_partner_names_for(@perspective_agent.name)
      all.select { |a| partner_names.include?(a.name) }
    else
      all
    end
  end

  def agent_not_found
    head :not_found
  end
end
