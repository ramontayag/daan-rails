module Daan
  class CreateMessage
    def self.call(chat, role:, content:, visible: true)
      message = chat.messages.create!(role: role, content: content, visible: visible)
      if visible
        message.broadcast_append_to(
          "chat_#{chat.id}",
          target: "messages",
          renderable: MessageComponent.new(role: role, body: content, dom_id: "message_#{message.id}")
        )
      end
      LlmJob.perform_later(chat) if role == "user"
      message
    end
  end
end
