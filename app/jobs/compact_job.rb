class CompactJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: ->(chat) { "chat_#{chat.id}" }

  def perform(chat)
    Daan::Core::CompactConversation.call(chat, chat.agent)
  end
end
