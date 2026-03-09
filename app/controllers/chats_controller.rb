class ChatsController < ApplicationController
  include SidebarAgents

  before_action :set_agents
  before_action :set_agent, only: :show

  def index
    # Root chat view — no agent selected yet
  end

  def show
    @chats = Chat.where(agent_name: @agent.name).order(created_at: :desc).includes(:messages)
  end

  private

  def set_agent
    @agent = Daan::AgentRegistry.find(params[:name])
  end
end
