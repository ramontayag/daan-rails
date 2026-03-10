class ChatMessageComponent < ViewComponent::Base
  def initialize(message:, results: {}, viewer_is_agent: false, hide_tools: false)
    @message         = message
    @results         = results
    @viewer_is_agent = viewer_is_agent
    @hide_tools      = hide_tools
  end

  private

  attr_reader :message, :results, :viewer_is_agent, :hide_tools

  def render?
    return false if message.role == "tool" || message.role == "system"
    return false if hide_tools && message.tool_calls.any? && message.content.blank?
    true
  end
end
