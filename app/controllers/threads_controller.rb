class ThreadsController < ApplicationController
  include Perspective

  before_action :set_perspective, only: :show
  before_action :set_agent_from_params, only: :create
  before_action :set_chat, only: :show

  def show
    @agent = Daan::AgentRegistry.find(@chat.agent_name)
    @chats = if perspective_name != "me" && @agent.name != perspective_name
      Chat.where(agent_name: @agent.name, parent_chat_id: perspective_tree_ids)
    else
      Chat.where(agent_name: @agent.name, parent_chat_id: nil)
    end.order(created_at: :desc).includes(:messages)
    @hide_tools = params[:show_tools] == "0"
    @show_tasks = params[:show_tasks] == "1"
  end

  def create
    @chat = Chat.create!(agent_name: @agent.name)
    Daan::CreateMessage.call(@chat, role: "user", content: message_params[:content])

    redirect_to chat_thread_path(@chat)
  end

  def default_url_options
    { show_tools: params[:show_tools], show_tasks: params[:show_tasks] }.compact
  end

  private

  def set_agent_from_params
    @agent = Daan::AgentRegistry.find(params[:agent_name])
  end

  def set_chat
    @chat = Chat.find(params[:id])
    if perspective_name != "me" && @chat.agent_name != perspective_name
      unless @chat.id.in?(perspective_tree_ids)
        redirect_to chat_agent_path(perspective_name)
      end
    end
  end

  def message_params
    params.require(:message).permit(:content)
  end
end
