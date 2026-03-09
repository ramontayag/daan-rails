module Daan
  class CreateMessage
    def self.call(chat, role:, content:)
      message = chat.messages.create!(role: role, content: content)
      message.broadcast_append_to(
        "chat_#{chat.id}",
        target: "messages",
        renderable: MessageComponent.new(role: role, body: content, dom_id: "message_#{message.id}")
      )
      message
    end
  end
end
