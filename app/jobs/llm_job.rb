class LlmJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: ->(chat) { "chat_#{chat.id}" }

  def perform(chat)
    Daan::ConversationRunner.call(chat)
  rescue => e
    chat.reload
    chat.fail! if chat.may_fail?
    chat.broadcast_agent_status
    raise
  end
end
