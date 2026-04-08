module Daan
  module Core
    class CreateMessage
    def self.call(chat, role:, content:, visible: true, broadcast_action: :append)
      message = chat.messages.create!(role: role, content: content, visible: visible)
      if visible
        message.public_send(:"broadcast_#{broadcast_action}_to",
          "chat_#{chat.id}",
          target: "messages",
          renderable: MessageComponent.new(role: role, body: content, dom_id: "message_#{message.id}", message: message)
        )
      end
      LlmJob.perform_later(chat) if role == "user"
      message
    end
    end
  end
end
