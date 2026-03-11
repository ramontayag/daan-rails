class ChatMessageComponent < ViewComponent::Base
  def initialize(message:, results: {}, hide_tools: false, agent_display_name: nil, user_display_name: nil)
    @message            = message
    @results            = results
    @hide_tools         = hide_tools
    @agent_display_name = agent_display_name
    @user_display_name  = user_display_name
  end

  private

  attr_reader :message, :results, :hide_tools, :agent_display_name, :user_display_name

  def render?
    return false if message.role == "tool" || message.role == "system"
    return false if hide_tools && message.tool_calls.any? && message.content.blank?
    true
  end

  def sender_name = message.role == "assistant" ? agent_display_name : user_display_name
end
