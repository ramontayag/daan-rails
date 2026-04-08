module Daan
  module Core
    module Chats
    class ReleaseWorkspace
      def self.call(chat)
        WorkspaceLock.release(chat: chat, agent_name: chat.agent_name)
        Rails.logger.info("[ReleaseWorkspace] chat_id=#{chat.id} released lock for agent=#{chat.agent_name}")
      end
    end
    end
  end
end
