# lib/daan/chats/finish_or_reenqueue.rb
module Daan
  module Chats
    class FinishOrReenqueue
      def self.call(chat, agent, response)
        if response.tool_call?
          step_count = chat.step_count
          if agent.max_steps_reached?(step_count)
            tag = "[FinishOrReenqueue] chat_id=#{chat.id}"
            Rails.logger.info("#{tag} max steps reached (#{agent.max_steps}), blocking")
            Turbo::StreamsChannel.broadcast_replace_to(
              "chat_#{chat.id}",
              target: "typing_indicator",
              renderable: TypingIndicatorComponent.new(typing: false)
            )
            chat.block! if chat.may_block?
            NotifyParent.on_termination(chat, :blocked)
            chat.broadcast_agent_status
          else
            warn_approaching_step_limit(chat, agent.max_steps - step_count)
            LlmJob.perform_later(chat)
          end
        else
          Turbo::StreamsChannel.broadcast_replace_to(
            "chat_#{chat.id}",
            target: "typing_indicator",
            renderable: TypingIndicatorComponent.new(typing: false)
          )
          finish_conversation(chat, agent)
        end
      end

      def self.finish_conversation(chat, agent)
        tag = "[FinishOrReenqueue] chat_id=#{chat.id}"
        chat.reload
        chat.finish! if chat.may_finish?
        Rails.logger.info("#{tag} finished status=#{chat.task_status} step=#{chat.step_count}/#{agent.max_steps}")
        chat.broadcast_agent_status
        chat.broadcast_chat_cost
        NotifyParent.on_completion(chat)
      end
      private_class_method :finish_conversation

      def self.warn_approaching_step_limit(chat, remaining)
        return unless remaining == 3 && chat.parent_chat.present?

        chat.messages.create!(
          role: "user",
          content: "[System] You have 2 steps of work remaining before this thread is blocked. " \
                   "Call report_back now with your current findings.",
          visible: false
        )
      end
      private_class_method :warn_approaching_step_limit
    end
  end
end
