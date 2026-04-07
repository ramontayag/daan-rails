class AgentActivityIndicatorComponent < ViewComponent::Base
  MESSAGES = {
    typing: "Typing...",
    queued: "Working on something else..."
  }.freeze

  def initialize(status:)
    @status = status
  end

  private

  attr_reader :status

  def message
    MESSAGES[status]
  end
end
