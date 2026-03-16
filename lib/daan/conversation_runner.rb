# lib/daan/conversation_runner.rb
module Daan
  class ConversationRunner
    def self.call(chat)
      agent = chat.agent

      start_conversation(chat)
      prepare_workspace(agent)
      enqueue_compaction_if_needed(chat)
      configure_llm(chat, agent)

      last_message_id = chat.messages.maximum(:id) || 0
      run_llm(chat)

      BroadcastMessagesJob.perform_later(chat, last_message_id)
      broadcast_typing(chat, false)
      finish_conversation(chat, agent)
    end

    def self.start_conversation(chat)
      chat.reload
      # Anthropic rejects empty text content blocks. Empty assistant messages
      # with no tool calls are streaming artifacts (created at start of stream,
      # content never written because the model only used tools or an error
      # interrupted). Delete them before replay — they have no value in history.
      orphaned_ids = chat.messages.where(role: "assistant", content: [ nil, "" ])
                                  .left_joins(:tool_calls).where(tool_calls: { id: nil })
                                  .ids
      Message.where(id: orphaned_ids).destroy_all if orphaned_ids.any?
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

    def self.enqueue_compaction_if_needed(chat)
      context_window = chat.model.context_window
      threshold = (context_window * 0.8).to_i
      # Integer division in COALESCE fallback is intentional — rough estimate,
      # 80% threshold provides sufficient headroom.
      token_sum = Message.active
                         .where(chat_id: chat.id)
                         .sum("COALESCE(output_tokens, LENGTH(content) / 4, 0)")
      CompactJob.perform_later(chat) if token_sum >= threshold
    end
    private_class_method :enqueue_compaction_if_needed

    def self.configure_llm(chat, agent)
      system_prompt = agent.system_prompt
      memories = retrieve_memories(chat)

      if memories.any?
        memory_lines = memories.map { |m|
          "[#{m[:metadata]["confidence"] || "?"}] [#{m[:metadata]["type"]}] #{m[:title]} (#{m[:file_path]})"
        }.join("\n")
        system_prompt = "#{system_prompt}\n\n## Relevant memories\n#{memory_lines}"
      end

      chat
        .with_model(agent.model_name)
        .with_instructions(system_prompt)
        .with_tools(*agent.tools(chat: chat))
    end
    private_class_method :configure_llm

    def self.retrieve_memories(chat)
      query = chat.messages.where(role: "user").last&.content
      return [] if query.blank?

      index = Daan::Memory.storage.semantic_index
      return [] unless Daan::Memory.storage.size > 0

      index.search(query: query, top_k: 5)
    rescue => e
      Rails.logger.warn("Memory retrieval failed: #{e.message}")
      []
    end
    private_class_method :retrieve_memories

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
