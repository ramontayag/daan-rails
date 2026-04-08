module Daan
  module Core
    module Chats
    class RunStep
      def self.call(chat, context_user_message_id:)
        tag = "[RunStep] chat_id=#{chat.id}"
        Rails.logger.info("#{tag} calling LLM model=#{chat.model_id}")
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = chat.step
        elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at).round(1)
        Rails.logger.info("#{tag} complete elapsed=#{elapsed}s tool_call=#{response.tool_call?}")
        chat.messages.where(role: "assistant").order(:id).last
            &.update_columns(context_user_message_id: context_user_message_id)
        broadcast_step(chat, response)
        chat.broadcast_chat_cost
        response
      rescue => e
        tag = "[RunStep] chat_id=#{chat.id}"
        Rails.logger.error("#{tag} LLM failed error=#{e.class}: #{e.message}")
        Rails.logger.error("#{tag} #{e.backtrace&.first(10)&.join("\n")}")
        chat.fail!
        chat.broadcast_agent_status
        chat.broadcast_chat_cost
        Turbo::StreamsChannel.broadcast_replace_to(
          "chat_#{chat.id}",
          target: "agent_activity_indicator",
          renderable: AgentActivityIndicatorComponent.new(status: nil)
        )
        begin
          NotifyParent.on_termination(chat, :failed)
        rescue => notify_error
          Rails.logger.error("#{tag} parent notification failed: #{notify_error.class}: #{notify_error.message}")
        end
        raise
      end

      def self.broadcast_step(chat, response)
        return unless response.role.to_s == "assistant"

        tool_call_ids = response.tool_calls&.keys&.map(&:to_s) || []
        results = if tool_call_ids.any?
          Message.where(role: "tool", tool_call_id: tool_call_ids)
                 .index_by(&:tool_call_id)
                 .transform_values(&:content)
        else
          {}
        end

        ar_message = response.is_a?(Message) ? response : chat.messages
                       .where(role: "assistant")
                       .order(:id)
                       .last
        return unless ar_message

        Turbo::StreamsChannel.broadcast_append_to(
          "chat_#{chat.id}",
          target: "messages",
          renderable: ChatMessageComponent.new(message: ar_message, results: results)
        )
      end
      private_class_method :broadcast_step
    end
    end
  end
end
