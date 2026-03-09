class ThreadsController < ApplicationController
  include SidebarAgents

  before_action :set_agents, only: :show
  before_action :set_agent_from_params, only: :create
  before_action :set_chat, only: :show

  def show
    @agent = Daan::AgentRegistry.find(@chat.agent_name)
    @chats = Chat.where(agent_name: @agent.name).order(created_at: :desc).includes(:messages)
  end

  def create
    @chat = Chat.create!(agent_name: @agent.name)
    Daan::CreateMessage.call(@chat, role: "user", content: message_params[:content])
    LlmJob.perform_later(@chat)
    redirect_to chat_thread_path(@chat)
  end

  private

  def set_agent_from_params
    @agent = Daan::AgentRegistry.find(params[:agent_name])
  end

  def set_chat
    @chat = Chat.find(params[:id])
  end

  def message_params
    params.require(:message).permit(:content)
  end
end
