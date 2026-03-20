# lib/daan/conversation_runner.rb
module Daan
  class ConversationRunner
    def self.call(chat)
      tag = "[ConversationRunner] chat_id=#{chat.id} agent=#{chat.agent_name}"
      agent = chat.agent

      start_conversation(chat)
      prepare_workspace(agent)
      enqueue_compaction_if_needed(chat)
      configure_llm(chat, agent)

      last_message_id = chat.messages.maximum(:id) || 0
      Rails.logger.info("#{tag} calling LLM model=#{chat.model_id}")
      llm_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      run_llm(chat)
      llm_elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - llm_started_at).round(1)
      Rails.logger.info("#{tag} LLM complete elapsed=#{llm_elapsed}s")

      BroadcastMessagesJob.perform_later(chat, last_message_id)
      broadcast_typing(chat, false)
      finish_conversation(chat, agent)
    end

    def self.start_conversation(chat)
      tag = "[ConversationRunner] chat_id=#{chat.id}"
      chat.reload
      # Anthropic rejects empty text content blocks. Empty assistant messages
      # with no tool calls are streaming artifacts (created at start of stream,
      # content never written because the model only used tools or an error
      # interrupted). Delete them before replay — they have no value in history.
      orphaned_ids = chat.messages.where(role: "assistant", content: [ nil, "" ])
                                  .left_joins(:tool_calls).where(tool_calls: { id: nil })
                                  .ids
      if orphaned_ids.any?
        Rails.logger.info("#{tag} cleaning #{orphaned_ids.size} orphaned assistant messages")
        Message.where(id: orphaned_ids).destroy_all
      end
      chat.continue! if chat.may_continue?
      chat.start!    if chat.may_start?
      Rails.logger.info("#{tag} started status=#{chat.task_status} message_count=#{chat.messages.count}")
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

    def self.build_system_prompt(chat, agent)
      prompt = agent.system_prompt
      prompt = append_memories(prompt, chat)
      prompt = append_steps(prompt, chat)
      prompt
    end

    def self.configure_llm(chat, agent)
      system_prompt = build_system_prompt(chat, agent)

      chat
        .with_model(agent.model_name)
        .with_instructions(system_prompt)
        .with_tools(*agent.tools(chat: chat))
    end
    private_class_method :configure_llm

    def self.append_memories(prompt, chat)
      memories = retrieve_memories(chat)
      return prompt unless memories.any?

      memory_lines = memories.map { |m|
        "[#{m[:metadata]["confidence"] || "?"}] [#{m[:metadata]["type"]}] #{m[:title]} (#{m[:file_path]})"
      }.join("\n")
      "#{prompt}\n\n## Relevant memories\n#{memory_lines}"
    end
    private_class_method :append_memories

    def self.append_steps(prompt, chat)
      steps = chat.chat_steps.to_a
      return prompt unless steps.any?

      lines = steps.map do |step|
        marker = case step.status
        when "completed"   then "[x]"
        when "in_progress" then "[in progress]"
        else                    "[ ]"
        end
        "#{step.position}. #{marker} #{step.title}"
      end

      "#{prompt}\n\n## Your Current Steps\n#{lines.join("\n")}"
    end
    private_class_method :append_steps

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
      tag = "[ConversationRunner] chat_id=#{chat.id}"
      Rails.logger.error("#{tag} LLM failed error=#{e.class}: #{e.message}")
      Rails.logger.error("#{tag} #{e.backtrace&.first(10)&.join("\n")}")
      chat.fail!
      chat.broadcast_agent_status
      broadcast_typing(chat, false)
      begin
        notify_parent_of_termination(chat, :failed)
      rescue => notify_error
        Rails.logger.error("#{tag} parent notification failed: #{notify_error.class}: #{notify_error.message}")
      end
      raise
    end
    private_class_method :run_llm

    def self.finish_conversation(chat, agent)
      tag = "[ConversationRunner] chat_id=#{chat.id}"
      chat.reload
      chat.increment!(:turn_count)
      remaining = agent.max_turns - chat.turn_count

      if agent.max_turns_reached?(chat.turn_count)
        Rails.logger.info("#{tag} max turns reached (#{agent.max_turns}), blocking")
        chat.block!   if chat.may_block?
        notify_parent_of_termination(chat, :blocked)
      else
        warn_approaching_turn_limit(chat, remaining)
        chat.finish!  if chat.may_finish?
      end
      Rails.logger.info("#{tag} finished status=#{chat.task_status} turn=#{chat.turn_count}/#{agent.max_turns}")
      chat.broadcast_agent_status
    end
    private_class_method :finish_conversation

    def self.warn_approaching_turn_limit(chat, remaining)
      return unless remaining == 3 && chat.parent_chat.present?

      chat.messages.create!(
        role: "user",
        content: "[System] You have 2 turns of work remaining before this thread is blocked. " \
                 "Call report_back now with your current findings.",
        visible: false
      )
    end
    private_class_method :warn_approaching_turn_limit

    def self.notify_parent_of_termination(chat, status)
      return unless chat.parent_chat.present?

      agent = Daan::AgentRegistry.find(chat.agent_name)
      last_assistant = chat.messages.where(role: "assistant").last
      last_content = last_assistant&.content.presence&.truncate(500) || "No response recorded."

      reason = case status
      when :blocked then "They reached the maximum turn limit of #{agent.max_turns}."
      when :failed  then "An error occurred during execution."
      end

      Daan::CreateMessage.call(
        chat.parent_chat,
        role: "user",
        content: "[System] #{agent.display_name}'s thread is now #{status}. " \
                 "#{reason} Their last message: #{last_content}",
        visible: false
      )
    end
    private_class_method :notify_parent_of_termination

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

      # Broadcast header stats update after all messages have been processed
      Turbo::StreamsChannel.broadcast_replace_to(
        "chat_#{chat.id}",
        target: "chat_header_stats",
        renderable: ChatHeaderStatsComponent.new(chat: chat)
      )
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
