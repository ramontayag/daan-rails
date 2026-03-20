class ThreadPanelComponent < ViewComponent::Base
  def initialize(chat:, perspective_name:, hide_tools: false, show_tasks: nil)
    @chat             = chat
    @perspective_name = perspective_name
    @hide_tools       = hide_tools
    @show_tasks       = show_tasks
  end

  private

  attr_reader :chat, :hide_tools

  def show_tasks
    return @show_tasks unless @show_tasks.nil?
    helpers.params[:show_tasks] == "1"
  end

  def readonly
    @perspective_name != "me"
  end

  def chat_messages
    @chat_messages ||= chat.messages.active.where(visible: true).includes(:tool_calls)
                           .order(Arel.sql("compacted_messages_count > 0 DESC"), :created_at)
  end

  def tool_results
    @tool_results ||= chat_messages.select { |m| m.role == "tool" }.index_by(&:tool_call_id).transform_values(&:content)
  end
end
