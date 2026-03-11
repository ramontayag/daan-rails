class ChatsController < ApplicationController
  include Perspective

  before_action :set_perspective
  before_action :set_agent, only: :show

  def index
    redirect_to chat_agent_path(@perspective_agent.name) if @perspective_agent
  end

  def show
    @chats = if perspective_name != "me" && @agent.name != perspective_name
      Chat.where(agent_name: @agent.name, parent_chat_id: perspective_tree_ids)
          .or(Chat.where(agent_name: @agent.name, id: perspective_ancestor_ids))
    else
      Chat.where(agent_name: @agent.name, parent_chat_id: nil)
    end.order(created_at: :desc).includes(:messages)
  end

  private

  def set_agent
    @agent = Daan::AgentRegistry.find(params[:name])
  end
end
