class ChatsController < ApplicationController
  before_action :set_agents
  before_action :set_agent, only: %i[show create_message]

  rescue_from KeyError, with: :agent_not_found

  def index
    @agent = @agents.first
    render :show if @agent
  end

  def show
    @chat = Chat.where(agent_name: @agent.name).order(created_at: :desc).first
  end

  def create_message
    @chat = Chat.where(agent_name: @agent.name).order(created_at: :desc).first ||
            Chat.create!(agent_name: @agent.name)
    @chat.continue! if @chat.may_continue?
    Daan::CreateMessage.call(@chat, role: "user", content: message_params[:content])
    LlmJob.perform_later(@chat)
    redirect_to agent_chat_path(@agent)
  end

  private

  def set_agents
    @agents = Daan::AgentRegistry.all
  end

  def set_agent
    @agent = Daan::AgentRegistry.find(params[:agent_name])
  end

  def message_params
    params.require(:message).permit(:content)
  end

  def agent_not_found
    head :not_found
  end
end
