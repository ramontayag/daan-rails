module Daan
  module Chats
    class InjectWorkspaceOrientation
      def self.call(chat, _workspace)
        chat.messages.create!(
          role: "user",
          content: "#{Daan::SystemTag::PREFIX} Workspace was used by another chat since your last run. " \
                   "Check the workspace state before proceeding.",
          visible: false
        )
        Rails.logger.info("[InjectWorkspaceOrientation] chat_id=#{chat.id} injected workspace orientation")
      end
    end
  end
end
