class ChatMessageComponent < ViewComponent::Base
  def initialize(message:, results: {})
    @message = message
    @results = results
  end

  private

  attr_reader :message, :results

  def render?
    message.role != "tool" && message.role != "system"
  end
end
