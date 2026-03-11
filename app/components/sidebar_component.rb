class SidebarComponent < ViewComponent::Base
  def initialize(current_perspective:, current_agent: nil)
    @current_perspective = current_perspective
    @current_agent       = current_agent
  end

  private

  attr_reader :current_perspective, :current_agent

  def agents
    Daan::AgentRegistry.all.reject { |a| a.name == current_perspective }
  end

  def in_agent_perspective?
    current_perspective != "me"
  end
end
