# lib/daan/chats/notify_parent.rb
module Daan
  module Chats
    class NotifyParent
      def self.on_completion(chat)
        return unless chat.parent_chat.present?

        agent = Daan::AgentRegistry.find(chat.agent_name)

        unless agent_reported_back?(chat, agent)
          last_content = chat.messages.where(role: "assistant").last.content.truncate(500)
          Daan::CreateMessage.call(
            chat.parent_chat,
            role: "user",
            content: "#{Daan::SystemTag::PREFIX} #{agent.display_name} completed their task without calling report_back. " \
                     "Their last message: #{last_content}",
            visible: false
          )
        end

        LlmJob.perform_later(chat.parent_chat)
      end

      def self.on_termination(chat, status)
        return unless chat.parent_chat.present?

        agent = Daan::AgentRegistry.find(chat.agent_name)
        last_assistant = chat.messages.where(role: "assistant").last
        last_content = last_assistant&.content.presence&.truncate(500) || "No response recorded."

        reason = case status
        when :blocked then "They reached the maximum step limit of #{agent.max_steps}."
        when :failed  then "An error occurred during execution."
        end

        Daan::CreateMessage.call(
          chat.parent_chat,
          role: "user",
          content: "#{Daan::SystemTag::PREFIX} #{agent.display_name}'s thread is now #{status}. " \
                   "#{reason} Their last message: #{last_content}",
          visible: false
        )

        LlmJob.perform_later(chat.parent_chat)
      end

      def self.agent_reported_back?(chat, agent)
        last_task_message = chat.messages.where(role: "user").last
        return false unless last_task_message

        chat.parent_chat.messages
            .where(role: "user")
            .where_created_at_gt(last_task_message.created_at)
            .where_content_like("#{Daan::SystemTag::PREFIX} #{agent.display_name} reported back: %")
            .exists?
      end
      private_class_method :agent_reported_back?
    end
  end
end
