module Daan
  module Core
    class ConversationRunner
    def self.call(chat)
      agent = chat.agent

      chat.reload
      return if skip_already_responded!(chat)

      acquire_result = Chats::AcquireWorkspace.call(chat)
      return unless acquire_result

      if acquire_result.previous_holder_chat_id
        Chats::InjectWorkspaceOrientation.call(chat, agent.workspace)
      end

      context_user_message_id = chat.messages.where(role: "user").maximum(:id)

      Chats::StartConversation.call(chat)
      Chats::PrepareWorkspace.call(agent)
      Chats::EnqueueCompaction.call(chat)
      Chats::ConfigureLlm.call(chat, agent)

      response, hooks = Chats::RunStepWithHooks.call(chat, context_user_message_id: context_user_message_id)
      Chats::FinishOrReenqueue.call(chat, agent, response, hooks: hooks)
    end

    def self.skip_already_responded!(chat)
      return false unless already_responded?(chat)

      Rails.logger.info("[ConversationRunner] chat_id=#{chat.id} skipping — last user message already has a response")
      if chat.in_progress?
        chat.finish!
        chat.broadcast_agent_status
        chat.broadcast_chat_cost
        Chats::NotifyParent.on_completion(chat)
      end
      Chats::ReleaseWorkspace.call(chat)
      true
    end
    private_class_method :skip_already_responded!

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
end
