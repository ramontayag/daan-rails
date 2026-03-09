# lib/daan/conversation_runner.rb
module Daan
  class ConversationRunner
    def self.call(chat)
      return unless chat.may_start?

      agent = chat.agent

      chat.start!
      chat.broadcast_agent_status
      broadcast_typing(chat, true)

      FileUtils.mkdir_p(agent.workspace) if agent.workspace

      # Capture after with_model/with_instructions (which persist system messages to DB)
      # so broadcast_new_messages only picks up messages produced by complete.
      chat
        .with_model(agent.model_name)
        .with_instructions(agent.system_prompt)
        .with_tools(*agent.tools)

      last_message_id = chat.messages.maximum(:id) || 0

      begin
        chat
          .on_tool_call { |tc| broadcast_tool_call_running(chat, tc) }
          .complete
      rescue => e
        begin
          chat.fail!
        rescue AASM::InvalidTransition
          # already in a terminal state
        end
        chat.broadcast_agent_status
        broadcast_typing(chat, false)
        raise
      end

      broadcast_new_messages(chat, last_message_id)
      broadcast_typing(chat, false)

      chat.increment!(:turn_count)
      agent.max_turns_reached?(chat.turn_count) ? chat.block! : chat.finish!
      chat.broadcast_agent_status
    end

    # Fires before a tool executes — appends ToolCallComponent in "running..." state.
    def self.broadcast_tool_call_running(chat, tc)
      ar_tool_call = ToolCall.find_by(tool_call_id: tc.id)
      return unless ar_tool_call

      Turbo::StreamsChannel.broadcast_append_to(
        "chat_#{chat.id}",
        target: "messages",
        renderable: ToolCallComponent.new(tool_call: ar_tool_call)
      )
    end
    private_class_method :broadcast_tool_call_running

    # Fires after complete — replaces tool call blocks (now with result) and appends text messages.
    def self.broadcast_new_messages(chat, since_id)
      chat.messages
          .includes(:tool_calls)
          .where("messages.id > ?", since_id)
          .order(:id)
          .each do |message|
        next if message.role == "tool"
        next if message.role == "user"

        if message.tool_calls.any?
          message.tool_calls.each do |tool_call|
            Turbo::StreamsChannel.broadcast_replace_to(
              "chat_#{chat.id}",
              target: "tool_call_#{tool_call.id}",
              renderable: ToolCallComponent.new(tool_call: tool_call)
            )
          end
        else
          Turbo::StreamsChannel.broadcast_append_to(
            "chat_#{chat.id}",
            target: "messages",
            renderable: MessageComponent.new(role: message.role, body: message.content,
                                            dom_id: "message_#{message.id}")
          )
        end
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
