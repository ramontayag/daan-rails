class ChatsController < ApplicationController
  before_action :set_agents
  before_action :set_agent, only: %i[show create_message]

  rescue_from KeyError, with: :agent_not_found

  def index
    @agent = @agents.first
    render :show if @agent
  end

  def show
    @chat = current_chat_for(@agent)
  end

  def create_message
    @chat = current_chat_for(@agent) || Chat.create!(agent_name: @agent.name)
    @chat.messages.create!(role: "user", content: message_params[:content])
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

  def current_chat_for(agent)
    Chat.where(agent_name: agent.name, task_status: %w[pending in_progress])
        .order(created_at: :desc)
        .first
  end

  def message_params
    params.require(:message).permit(:content)
  end

  def agent_not_found
    head :not_found
  end
end
