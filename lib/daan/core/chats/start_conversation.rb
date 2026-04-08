module Daan
  module Core
    module Chats
    class StartConversation
      def self.call(chat)
        tag = "[StartConversation] chat_id=#{chat.id}"
        chat.reload

        orphaned_ids = chat.messages.where(role: "assistant", content: [ nil, "" ])
                                    .left_joins(:tool_calls).where(tool_calls: { id: nil })
                                    .ids
        if orphaned_ids.any?
          Rails.logger.info("#{tag} cleaning #{orphaned_ids.size} orphaned assistant messages")
          Message.where(id: orphaned_ids).destroy_all
        end

        chat.continue! if chat.may_continue?
        chat.start!    if chat.may_start?
        Rails.logger.info("#{tag} started status=#{chat.task_status} message_count=#{chat.messages.count}")
        chat.broadcast_agent_status
        Turbo::StreamsChannel.broadcast_replace_to(
          "chat_#{chat.id}",
          target: "agent_activity_indicator",
          renderable: AgentActivityIndicatorComponent.new(status: :typing)
        )
      end
    end
    end
  end
end
