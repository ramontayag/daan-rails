class MessagesController < ApplicationController
  before_action :set_chat

  def create
    Daan::CreateMessage.call(@chat, role: "user", content: message_params[:content])
    
    respond_to do |format|
      format.turbo_stream { head :ok }
      format.html { redirect_to chat_thread_path(@chat) }
    end
  end

  private

  def set_chat
    @chat = Chat.find(params[:thread_id])
  end

  def message_params
    params.require(:message).permit(:content)
  end
end