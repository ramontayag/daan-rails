class ChatMessageComponent < ViewComponent::Base
  def initialize(message:, results: {}, viewer_is_agent: false)
    @message         = message
    @results         = results
    @viewer_is_agent = viewer_is_agent
  end

  private

  attr_reader :message, :results, :viewer_is_agent

  def render?
    message.role != "tool" && message.role != "system"
  end
end
