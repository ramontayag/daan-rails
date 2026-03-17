class MessagesController < ApplicationController
  before_action :set_chat

  def create
    Daan::CreateMessage.call(@chat, role: "user", content: message_params[:content])
    head :no_content
  end

  private

  def set_chat
    @chat = Chat.find(params[:thread_id])
  end

  def message_params
    params.require(:message).permit(:content)
  end
end