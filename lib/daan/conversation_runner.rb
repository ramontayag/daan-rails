# lib/daan/conversation_runner.rb
module Daan
  class ConversationRunner
    def self.call(chat)
      agent = chat.agent

      chat.reload
      if already_responded?(chat)
        Rails.logger.info("[ConversationRunner] chat_id=#{chat.id} skipping — last user message already has a response")
        return
      end

      context_user_message_id = chat.messages.where(role: "user").maximum(:id)

      Chats::StartConversation.call(chat)
      Chats::PrepareWorkspace.call(agent)
      Chats::EnqueueCompaction.call(chat)
      Chats::ConfigureLlm.call(chat, agent)

      response = Chats::RunStep.call(chat, context_user_message_id: context_user_message_id)
      Chats::FinishOrReenqueue.call(chat, agent, response)
    end

    def self.already_responded?(chat)
      last_user_message      = chat.messages.where(role: "user").last
      last_assistant_message = chat.messages.where(role: "assistant").last
      return false unless last_user_message && last_assistant_message
      return false if last_assistant_message.context_user_message_id.nil?
      return false unless last_assistant_message.context_user_message_id >= last_user_message.id

      # If there's a tool result after the last assistant message, the conversation
      # is mid-flight (tool was called, result received, next step pending) — not done.
      !chat.messages.where(role: "tool").since_id(last_assistant_message.id).exists?
    end
    private_class_method :already_responded?
  end
end
