module Daan
  module Core
    module Chats
    class RunStepWithHooks
      def self.call(chat, context_user_message_id:)
        hooks = collect_hooks(chat.agent)
        dispatch_before_llm_call(hooks, chat)
        dispatch_before_conversation(hooks, chat) if chat.step_count == 0

        Thread.current[:daan_active_hooks] = { hooks: hooks, chat: chat }
        begin
          response = RunStep.call(chat, context_user_message_id: context_user_message_id)
        rescue => e
          dispatch_after_conversation(hooks, chat, :failed)
          raise
        ensure
          Thread.current[:daan_active_hooks] = nil
        end

        [ response, hooks ]
      end

      def self.collect_hooks(agent)
        Hook::Registry.agent_hooks(agent.hook_names) +
          Hook::Registry.tool_hooks
      end
      private_class_method :collect_hooks

      def self.dispatch_before_llm_call(hooks, chat)
        last_assistant = chat.messages.where(role: "assistant").order(:id).last
        last_tool_calls = last_assistant ? ToolCall.where(message_id: last_assistant.id) : []

        hooks.each do |h|
          h.before_llm_call(chat: chat, last_tool_calls: last_tool_calls)
        rescue => e
          Rails.logger.error("[Hook] #{h.class} raised during before_llm_call: #{e.message}")
        end
      end
      private_class_method :dispatch_before_llm_call

      def self.dispatch_before_conversation(hooks, chat)
        hooks.each do |h|
          h.before_conversation(chat: chat)
        rescue => e
          Rails.logger.error("[Hook] #{h.class} raised during before_conversation: #{e.message}")
        end
      end
      private_class_method :dispatch_before_conversation

      def self.dispatch_after_conversation(hooks, chat, status)
        return unless status
        hooks.each do |h|
          h.after_conversation(chat: chat, status: status)
        rescue => e
          Rails.logger.error("[Hook] #{h.class} raised during after_conversation: #{e.message}")
        end
      end
    end
    end
  end
end
