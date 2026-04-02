# lib/daan/conversation_runner.rb
module Daan
  class ConversationRunner
    def self.call(chat)
      agent = chat.agent

      chat.reload
      if already_responded?(chat)
        Rails.logger.info("[ConversationRunner] chat_id=#{chat.id} skipping — last user message already has a response")
        if chat.in_progress?
          chat.finish!
          chat.broadcast_agent_status
          chat.broadcast_chat_cost
          Chats::NotifyParent.on_completion(chat)
        end
        return
      end

      context_user_message_id = chat.messages.where(role: "user").maximum(:id)

      Chats::StartConversation.call(chat)
      Chats::PrepareWorkspace.call(agent)
      Chats::EnqueueCompaction.call(chat)
      Chats::ConfigureLlm.call(chat, agent)

      hooks = Daan::Core::Hook::Registry.agent_hooks(agent.hook_names) +
              Daan::Core::Hook::Registry.tool_hooks
      last_tool_calls = last_tool_calls_for(chat)
      hooks.each do |h|
        h.before_llm_call(chat: chat, last_tool_calls: last_tool_calls)
      rescue => e
        Rails.logger.error("[Hook] #{h.class} raised during before_llm_call: #{e.message}")
      end

      if chat.step_count == 0
        hooks.each do |h|
          h.before_conversation(chat: chat)
        rescue => e
          Rails.logger.error("[Hook] #{h.class} raised during before_conversation: #{e.message}")
        end
      end

      Thread.current[:daan_active_hooks] = { hooks: hooks, chat: chat }
      begin
        response = Chats::RunStep.call(chat, context_user_message_id: context_user_message_id)
      rescue => e
        dispatch_after_conversation(hooks, chat, :failed)
        raise
      ensure
        Thread.current[:daan_active_hooks] = nil
      end
      Chats::FinishOrReenqueue.call(chat, agent, response)
      dispatch_after_conversation(hooks, chat, terminal_status_for(chat.reload))
    end

    def self.last_tool_calls_for(chat)
      last_assistant = chat.messages.where(role: "assistant").order(:id).last
      return [] unless last_assistant
      ToolCall.where(message_id: last_assistant.id)
    end
    private_class_method :last_tool_calls_for

    def self.terminal_status_for(chat)
      return :completed if chat.completed?
      return :blocked   if chat.blocked?
      return :failed    if chat.failed?
      nil
    end
    private_class_method :terminal_status_for

    def self.dispatch_after_conversation(hooks, chat, status)
      return unless status
      hooks.each do |h|
        h.after_conversation(chat: chat, status: status)
      rescue => e
        Rails.logger.error("[Hook] #{h.class} raised during after_conversation: #{e.message}")
      end
    end
    private_class_method :dispatch_after_conversation

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
