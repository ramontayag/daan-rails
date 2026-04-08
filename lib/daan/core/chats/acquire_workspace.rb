module Daan
  module Core
    module Chats
    class AcquireWorkspace
      RETRY_DELAY = 5.seconds

      def self.call(chat)
        result = WorkspaceLock.acquire(chat: chat, agent_name: chat.agent_name)

        if result.acquired?
          Rails.logger.info("[AcquireWorkspace] chat_id=#{chat.id} acquired lock for agent=#{chat.agent_name}")
          result
        else
          Rails.logger.info("[AcquireWorkspace] chat_id=#{chat.id} lock held for agent=#{chat.agent_name}, re-enqueuing in #{RETRY_DELAY}")
          Turbo::StreamsChannel.broadcast_replace_to(
            "chat_#{chat.id}",
            target: "agent_activity_indicator",
            renderable: AgentActivityIndicatorComponent.new(status: :queued)
          )
          LlmJob.set(wait: RETRY_DELAY).perform_later(chat)
          nil
        end
      end
    end
    end
  end
end
