module Daan
  class ConversationRunner
    def self.call(chat)
      agent = chat.agent
      chat.start!
      chat.broadcast_agent_status

      begin
        chat
          .with_model(agent.model_name)
          .with_instructions(agent.system_prompt)
          .complete
      rescue => e
        begin
          chat.fail!
        rescue AASM::InvalidTransition
          # already in a terminal state
        end
        chat.broadcast_agent_status
        raise
      end

      broadcast_last_assistant_message(chat)

      chat.increment!(:turn_count)
      agent.max_turns_reached?(chat.turn_count) ? chat.block! : chat.finish!
      chat.broadcast_agent_status
    end

    def self.broadcast_last_assistant_message(chat)
      message = chat.messages.where(role: "assistant").order(:created_at).last
      return unless message

      message.broadcast_append_to(
        "chat_#{chat.id}",
        target: "messages",
        renderable: MessageComponent.new(role: "assistant", body: message.content,
                                         dom_id: "message_#{message.id}")
      )
    end
    private_class_method :broadcast_last_assistant_message
  end
end
