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

  # Returns all chat IDs in the perspective agent's delegation tree so that
  # grandchild chats (e.g. CoS→EM→Dev) are visible when viewing Dev as CoS.
  # Hard cap at 3 hops — matches the current 3-agent topology (CoS→EM→Dev).
  def perspective_tree_ids
    ids = Chat.where(agent_name: perspective_name).pluck(:id)
    3.times do
      child_ids = Chat.where(parent_chat_id: ids).pluck(:id) - ids
      break if child_ids.empty?
      ids += child_ids
    end
    ids
  end
end
