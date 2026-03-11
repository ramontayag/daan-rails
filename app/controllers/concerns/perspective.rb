module Perspective
  extend ActiveSupport::Concern

  included do
    helper_method :perspective_name
  end

  private

  def set_perspective
    name = params[:perspective].presence
    if name && name != "me"
      @perspective_agent = Daan::AgentRegistry.find(name)
      @perspective_name  = name
    else
      @perspective_agent = nil
      @perspective_name  = "me"
    end
  end

  def perspective_name = @perspective_name || "me"

  def default_url_options
    perspective_name == "me" ? {} : { perspective: perspective_name }
  end

  # Returns all chat IDs reachable downward from the perspective agent's chats.
  # Used when a senior agent (e.g. CoS) views a junior agent's (e.g. Dev) chats.
  def perspective_tree_ids
    ids = Chat.where(agent_name: perspective_name).pluck(:id)
    loop do
      child_ids = Chat.where(parent_chat_id: ids).pluck(:id) - ids
      break if child_ids.empty?
      ids += child_ids
    end
    ids
  end

  # Returns the direct parent chat IDs of the perspective agent's chats.
  # Used when a junior agent (e.g. Dev) views the agent that delegated to it (e.g. EM).
  def perspective_ancestor_ids
    Chat.where(agent_name: perspective_name).select(:parent_chat_id)
  end
end
