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

      chat.increment!(:turn_count)
      agent.max_turns_reached?(chat.turn_count) ? chat.block! : chat.finish!
      chat.broadcast_agent_status
    end
  end
end
