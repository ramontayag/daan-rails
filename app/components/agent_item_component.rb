class AgentItemComponent < ViewComponent::Base
  def initialize(agent:, active: false)
    @agent = agent
    @active = active
  end

  private

  attr_reader :agent, :active

  def dot_classes = agent.busy? ? "bg-yellow-400" : "bg-green-400"
  def item_classes
    base = "flex items-center gap-2 p-2 rounded hover:bg-gray-800"
    active ? "#{base} bg-gray-800" : base
  end
end
