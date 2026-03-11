class BroadcastMessagesJob < ApplicationJob
  def perform(chat, since_id)
    Daan::ConversationRunner.broadcast_new_messages(chat, since_id)
  end
end
