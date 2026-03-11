class ThreadPanelComponent < ViewComponent::Base
  def initialize(chat:, perspective_name:, hide_tools: false)
    @chat             = chat
    @perspective_name = perspective_name
    @hide_tools       = hide_tools
  end

  private

  attr_reader :chat, :hide_tools

  def readonly
    @perspective_name != "me"
  end

  def agent_display_name
    chat.agent.display_name
  end

  def user_display_name
    chat.parent_chat ? chat.parent_chat.agent.display_name : "User"
  end

  def chat_messages
    @chat_messages ||= chat.messages.where(visible: true).includes(:tool_calls).order(:created_at)
  end

  def tool_results
    @tool_results ||= chat_messages.select { |m| m.role == "tool" }.index_by(&:tool_call_id).transform_values(&:content)
  end
end
