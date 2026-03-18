class ChatStepPanelComponent < ViewComponent::Base
  def initialize(chat:, show_tasks: nil)
    @chat = chat
    @show_tasks = show_tasks
  end

  private

  attr_reader :chat

  def show_tasks
    return @show_tasks unless @show_tasks.nil?
    helpers.params[:show_tasks] == "1"
  end

  def steps_exist?
    chat.chat_steps.any?
  end
end
