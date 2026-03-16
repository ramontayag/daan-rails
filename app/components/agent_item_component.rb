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
    # Use multiple methods to determine if this agent should be highlighted
    # This makes the highlighting more robust against object identity issues

    # Primary: use the passed active flag (maintains backward compatibility)
    return true if active

    # Fallback: if current_agent is provided, use name comparison
    # This guards against object identity issues
    if current_agent
      return agent.name == current_agent.name
    end

    false
  end

  def debug_attributes
    # Add data attributes for debugging highlighting issues
    return {} unless Rails.env.development?

    {
      "data-agent" => agent.name,
      "data-active" => active.to_s,
      "data-is-highlighted" => is_active_agent?.to_s,
      "data-current-agent" => current_agent&.name,
      "data-agent-object-id" => agent.object_id.to_s,
      "data-current-agent-object-id" => current_agent&.object_id&.to_s
    }
  end
end
