module Daan
  module Core
    class SearchChats < RubyLLM::Tool
      include Daan::Core::Tool.module(timeout: 10.seconds)

      description "Search across all chat history using Slack-like query syntax. " \
                  "Operators: with:agent_name (chats involving that agent), with:user (chats with human), " \
                  "from:user (human messages), from:agent_name (that agent's responses), " \
                  "before:YYYY-MM-DD, after:YYYY-MM-DD. Everything else is free-text search."
      param :query, desc: "Search query with optional operators (e.g. 'authentication with:developer after:2026-01-01')"

      RESULT_LIMIT = 10
      CONTEXT_WINDOW = 2

      def initialize(workspace: nil, chat: nil, storage: nil, agent_name: nil)
      end

      def execute(query:)
        operators, search_terms = parse_query(query)
        return "Error: no search terms provided. Include at least one word to search for." if search_terms.blank?

        message_ids = fts_search(search_terms)
        return "No results found for: #{search_terms}" if message_ids.empty?

        messages = Message.where(id: message_ids).includes(:chat)
        messages = apply_filters(messages, operators)
        messages = messages.order(created_at: :desc).limit(RESULT_LIMIT)

        return "No results found for: #{query}" if messages.empty?

        format_results(messages)
      end

      private

      def parse_query(query)
        operators = {}
        terms = []

        query.split(/\s+/).each do |token|
          case token
          when /\Awith:(.+)\z/
            (operators[:with] ||= []) << $1
          when /\Afrom:(.+)\z/
            (operators[:from] ||= []) << $1
          when /\Abefore:(.+)\z/
            begin
              operators[:before] = Date.parse($1)
            rescue Date::Error
              terms << token
            end
          when /\Aafter:(.+)\z/
            begin
              operators[:after] = Date.parse($1)
            rescue Date::Error
              terms << token
            end
          else
            terms << token
          end
        end

        [ operators, terms.join(" ") ]
      end

      def fts_search(terms)
        escaped = terms.split(/\s+/).map { |t| '"' + t.gsub('"', '""') + '"' }.join(" ")
        sanitized = ActiveRecord::Base.connection.quote_string(escaped)
        rows = ActiveRecord::Base.connection.execute(
          "SELECT rowid FROM messages_fts WHERE messages_fts MATCH '#{sanitized}'"
        )
        rows.map { |r| r["rowid"] }
      end

      def apply_filters(messages, operators)
        if operators[:with]
          chat_ids = chat_ids_for_with(operators[:with])
          messages = messages.where(chat_id: chat_ids) if chat_ids.present?
        end

        if operators[:from]
          messages = apply_from_filter(messages, operators[:from])
        end

        if operators[:before]
          messages = messages.where(Message.arel_table[:created_at].lt(operators[:before].beginning_of_day))
        end

        if operators[:after]
          messages = messages.where(Message.arel_table[:created_at].gt(operators[:after].end_of_day))
        end

        messages
      end

      def chat_ids_for_with(names)
        ids = Set.new
        names.each do |name|
          if name == "user"
            ids.merge(Chat.where(parent_chat_id: nil).pluck(:id))
          else
            ids.merge(Chat.where(agent_name: name).pluck(:id))
            ids.merge(Chat.where(parent_chat: Chat.where(agent_name: name)).pluck(:id))
          end
        end
        ids
      end

      def apply_from_filter(messages, names)
        conditions = names.map do |name|
          if name == "user"
            Message.arel_table[:role].eq("user")
          else
            Message.arel_table[:role].eq("assistant")
              .and(Message.arel_table[:chat_id].in(
                Chat.where(agent_name: name).select(:id).arel
              ))
          end
        end

        combined = conditions.reduce { |a, b| a.or(b) }
        messages.where(combined)
      end

      def format_results(messages)
        messages.map { |msg| format_one(msg) }.join("\n\n---\n\n")
      end

      def format_one(msg)
        chat = msg.chat
        header = "Chat ##{chat.id} (#{chat.agent_name}, #{chat.task_status}) — #{msg.created_at.strftime('%Y-%m-%d %H:%M')}"

        before_msgs = chat.messages.where(role: %w[user assistant])
          .where(Message.arel_table[:id].lt(msg.id))
          .order(id: :desc).limit(CONTEXT_WINDOW).to_a.reverse

        after_msgs = chat.messages.where(role: %w[user assistant])
          .where(Message.arel_table[:id].gt(msg.id))
          .order(:id).limit(CONTEXT_WINDOW).to_a

        surrounding = before_msgs + [ msg ] + after_msgs

        context_lines = surrounding.map do |m|
          prefix = m.id == msg.id ? ">> " : "   "
          "#{prefix}[#{m.role}] #{m.content.to_s.truncate(200)}"
        end

        "#{header}\n#{context_lines.join("\n")}"
      end
    end
  end
end
