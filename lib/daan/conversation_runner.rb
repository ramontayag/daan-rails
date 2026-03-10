# lib/daan/conversation_runner.rb
module Daan
  class ConversationRunner
    def self.call(chat)
      agent = chat.agent

      start_conversation(chat)
      prepare_workspace(agent)
      configure_llm(chat, agent)

      last_message_id = chat.messages.maximum(:id) || 0
      run_llm(chat)

      broadcast_new_messages(chat, last_message_id)
      broadcast_typing(chat, false)
      finish_conversation(chat, agent)
    end

    def self.start_conversation(chat)
      chat.reload
      chat.continue! if chat.may_continue?
      chat.start!    if chat.may_start?
      chat.broadcast_agent_status
      broadcast_typing(chat, true)
    end
    private_class_method :start_conversation

    def self.prepare_workspace(agent)
      agent.workspace&.root&.mkpath
    end
    private_class_method :prepare_workspace

    def self.configure_llm(chat, agent)
      chat
        .with_model(agent.model_name)
        .with_instructions(agent.system_prompt)
        .with_tools(*agent.tools(chat: chat))
    end
    private_class_method :configure_llm

    def self.run_llm(chat)
      chat.complete
    rescue => e
      chat.fail!
      chat.broadcast_agent_status
      broadcast_typing(chat, false)
      raise
    end
    private_class_method :run_llm

    def self.finish_conversation(chat, agent)
      chat.reload
      chat.increment!(:turn_count)
      if agent.max_turns_reached?(chat.turn_count)
        chat.block!   if chat.may_block?
      else
        chat.finish!  if chat.may_finish?
      end
      chat.broadcast_agent_status
    end
    private_class_method :finish_conversation

    def self.broadcast_new_messages(chat, since_id)
      messages = chat.messages
                     .includes(:tool_calls)
                     .where("messages.id > ?", since_id)
                     .order(:id)

      results_by_tool_call_id = messages
        .select { |m| m.role == "tool" }
        .index_by(&:tool_call_id)
        .transform_values(&:content)

      messages.each do |message|
        next if message.role == "tool" || message.role == "user"

        Turbo::StreamsChannel.broadcast_append_to(
          "chat_#{chat.id}",
          target: "messages",
          renderable: ChatMessageComponent.new(message: message, results: results_by_tool_call_id)
        )
      end
    end
    private_class_method :broadcast_new_messages

    def self.broadcast_typing(chat, typing)
      Turbo::StreamsChannel.broadcast_replace_to(
        "chat_#{chat.id}",
        target: "typing_indicator",
        renderable: TypingIndicatorComponent.new(typing: typing)
      )
    end
    private_class_method :broadcast_typing
  end
end
