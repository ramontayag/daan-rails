module Daan
  module Core
    class ReadChat < RubyLLM::Tool
      include Daan::Core::Tool.module(timeout: 10.seconds)

      description "Read messages from a specific chat. Use after SearchChats to dive deeper " \
                  "into a conversation. Returns user and assistant messages only (no tool internals)."
      param :chat_id, desc: "ID of the chat to read"
      param :offset, desc: "Number of messages to skip (default: 0)", required: false
      param :limit, desc: "Number of messages to return (default: 20, max: 50)", required: false

      DEFAULT_LIMIT = 20
      MAX_LIMIT = 50

      def initialize(workspace: nil, chat: nil, storage: nil, agent_name: nil)
      end

      def execute(chat_id:, offset: 0, limit: DEFAULT_LIMIT)
        chat = Chat.find_by(id: chat_id)
        return "Error: Chat ##{chat_id} not found." unless chat

        offset = [ offset.to_i, 0 ].max
        limit = [ [ limit.to_i, 1 ].max, MAX_LIMIT ].min

        all_messages = chat.messages.where(role: %w[user assistant]).order(:id)
        total = all_messages.count
        window = all_messages.offset(offset).limit(limit)

        header = "Chat ##{chat.id} (#{chat.agent_name}, #{chat.task_status}) — " \
                 "#{total} messages, showing #{offset + 1}-#{[ offset + limit, total ].min}"

        lines = window.map do |msg|
          "[#{msg.created_at.strftime('%Y-%m-%d %H:%M')}] [#{msg.role}] #{msg.content}"
        end

        "#{header}\n\n#{lines.join("\n\n")}"
      end
    end
  end
end
