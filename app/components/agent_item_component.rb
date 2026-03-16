class AgentItemComponent < ViewComponent::Base
  def initialize(agent:, active: false, current_agent: nil)
    @agent = agent
    @active = active
    @current_agent = current_agent
  end

  private

  attr_reader :agent, :active, :current_agent

  def dot_classes = agent.busy? ? "bg-yellow-400" : "bg-green-400"
  
  def item_classes
    base = "flex items-center gap-2 p-2 rounded hover:bg-gray-800"
    is_active_agent? ? "#{base} bg-gray-800" : base
  end

  def is_active_agent?
    # Primary: explicit active flag (backward compatibility)
    return true if active
    
    # Fallback: name-based comparison for object identity issues
    current_agent&.name == agent.name
  end

  def debug_data_attributes
    return {} unless Rails.env.development?
    
    {
      data: {
        agent_name: agent.name,
        active_flag: active,
        current_agent_name: current_agent&.name,
        is_active: is_active_agent?,
        object_identity_match: current_agent == agent
      }
    }
  end
end