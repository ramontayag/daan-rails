class ChatMessageComponent < ViewComponent::Base
  def initialize(message:, chat: nil, results: {}, hide_tools: false, agent_display_name: nil, user_display_name: nil)
    @message            = message
    @chat               = chat
    @results            = results
    @hide_tools         = hide_tools
    @agent_display_name = agent_display_name
    @user_display_name  = user_display_name
  end

  private

  attr_reader :message, :results, :hide_tools

  def return_to_uri
    helpers.chat_thread_path(chat)
  end

  def chat
    @chat ||= message.chat
  end

  def agent_display_name
    @agent_display_name ||= chat.agent.display_name
  end

  def user_display_name
    @user_display_name ||= chat.parent_chat&.agent&.display_name || "User"
  end

  def render?
    return false if message.role == "tool" || message.role == "system"
    return false if hide_tools && message.tool_calls.any? && message.content.blank?
    true
  end

  def sender_name = message.role == "assistant" ? agent_display_name : user_display_name
end
