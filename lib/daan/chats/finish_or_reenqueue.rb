# lib/daan/chats/finish_or_reenqueue.rb
module Daan
  module Chats
    class FinishOrReenqueue
      def self.call(chat, agent, response)
        if !response.tool_call?
          finish_conversation(chat, agent)
        elsif agent.max_steps_reached?(chat.step_count)
          block_conversation(chat, agent)
        else
          continue_conversation(chat, agent)
        end
      end

      def self.block_conversation(chat, agent)
        tag = "[FinishOrReenqueue] chat_id=#{chat.id}"
        Rails.logger.info("#{tag} max steps reached (#{agent.max_steps}), blocking")
        ForceReportBack.call(chat)
        dismiss_agent_activity_indicator(chat)
        chat.block! if chat.may_block?
        ReleaseWorkspace.call(chat)
        NotifyParent.on_termination(chat, :blocked)
        chat.broadcast_agent_status
      end
      private_class_method :block_conversation

      def self.continue_conversation(chat, agent)
        warn_approaching_step_limit(chat, agent.max_steps - chat.step_count)
        LlmJob.perform_later(chat)
      end
      private_class_method :continue_conversation

      def self.finish_conversation(chat, agent)
        tag = "[FinishOrReenqueue] chat_id=#{chat.id}"
        dismiss_agent_activity_indicator(chat)
        chat.reload
        chat.finish! if chat.may_finish?
        ReleaseWorkspace.call(chat)
        Rails.logger.info("#{tag} finished status=#{chat.task_status} step=#{chat.step_count}/#{agent.max_steps}")
        chat.broadcast_agent_status
        chat.broadcast_chat_cost
        NotifyParent.on_completion(chat)
      end
      private_class_method :finish_conversation

      def self.dismiss_agent_activity_indicator(chat)
        Turbo::StreamsChannel.broadcast_replace_to(
          "chat_#{chat.id}",
          target: "agent_activity_indicator",
          renderable: AgentActivityIndicatorComponent.new(status: nil)
        )
      end
      private_class_method :dismiss_agent_activity_indicator

      def self.warn_approaching_step_limit(chat, remaining)
        return unless remaining == 3 && chat.parent_chat.present?

        chat.messages.create!(
          role: "user",
          content: "#{Daan::SystemTag::PREFIX} You have 3 steps of work remaining before this thread is blocked. " \
                   "Call report_back now with your current findings.",
          visible: false
        )
      end
      private_class_method :warn_approaching_step_limit
    end
  end
end
