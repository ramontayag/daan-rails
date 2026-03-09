class MessagesController < ApplicationController
  before_action :set_chat

  def create
    @chat.continue!
    Daan::CreateMessage.call(@chat, role: "user", content: message_params[:content])
    LlmJob.perform_later(@chat)
    redirect_to chat_thread_path(@chat)
  end

  private

  def set_chat
    @chat = Chat.find(params[:thread_id])
  end

  def message_params
    params.require(:message).permit(:content)
  end
end
