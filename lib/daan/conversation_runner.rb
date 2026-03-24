# lib/daan/conversation_runner.rb
module Daan
  class ConversationRunner
    def self.call(chat)
      tag = "[ConversationRunner] chat_id=#{chat.id} agent=#{chat.agent_name}"
      agent = chat.agent

      chat.reload
      if already_responded?(chat)
        Rails.logger.info("#{tag} skipping — last user message already has a response")
        return
      end

      context_user_message_id = chat.messages.where(role: "user").maximum(:id)

      start_conversation(chat)
      prepare_workspace(agent)
      enqueue_compaction_if_needed(chat)
      configure_llm(chat, agent)

        Rails.logger.info("#{tag} calling LLM model=#{chat.model_id}")
      llm_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = run_step(chat, context_user_message_id)
      llm_elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - llm_started_at).round(1)
      Rails.logger.info("#{tag} LLM step complete elapsed=#{llm_elapsed}s tool_call=#{response.tool_call?}")

      finish_or_reenqueue(chat, agent, response)
    end

    def self.start_conversation(chat)
      tag = "[ConversationRunner] chat_id=#{chat.id}"
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

    def self.run_step(chat, context_user_message_id)
      response = chat.step
      chat.messages.where(role: "assistant").order(:id).last
          &.update_columns(context_user_message_id: context_user_message_id)
      broadcast_step(chat, response)
      chat.broadcast_chat_cost
      response
    rescue => e
      tag = "[ConversationRunner] chat_id=#{chat.id}"
      Rails.logger.error("#{tag} LLM failed error=#{e.class}: #{e.message}")
      Rails.logger.error("#{tag} #{e.backtrace&.first(10)&.join("\n")}")
      chat.fail!
      chat.broadcast_agent_status
      chat.broadcast_chat_cost
      broadcast_typing(chat, false)
      begin
        notify_parent_of_termination(chat, :failed)
      rescue => notify_error
        Rails.logger.error("#{tag} parent notification failed: #{notify_error.class}: #{notify_error.message}")
      end
      raise
    end
    private_class_method :run_step

    def self.broadcast_step(chat, response)
      return unless response.role.to_s == "assistant"

      tool_call_ids = response.tool_calls&.keys&.map(&:to_s) || []
      results = if tool_call_ids.any?
        Message.where(role: "tool", tool_call_id: tool_call_ids)
               .index_by(&:tool_call_id)
               .transform_values(&:content)
      else
        {}
      end

      ar_message = response.is_a?(Message) ? response : chat.messages
                     .where(role: "assistant")
                     .order(:id)
                     .last
      return unless ar_message

      Turbo::StreamsChannel.broadcast_append_to(
        "chat_#{chat.id}",
        target: "messages",
        renderable: ChatMessageComponent.new(message: ar_message, results: results)
      )
    end
    private_class_method :broadcast_step

    def self.finish_or_reenqueue(chat, agent, response)
      if response.tool_call?
        step_count = chat.step_count
        if agent.max_steps_reached?(step_count)
          tag = "[ConversationRunner] chat_id=#{chat.id}"
          Rails.logger.info("#{tag} max steps reached (#{agent.max_steps}), blocking")
          broadcast_typing(chat, false)
          chat.block! if chat.may_block?
          notify_parent_of_termination(chat, :blocked)
          chat.broadcast_agent_status
        else
          warn_approaching_step_limit(chat, agent.max_steps - step_count)
          LlmJob.perform_later(chat)
        end
      else
        broadcast_typing(chat, false)
        finish_conversation(chat, agent)
      end
    end
    private_class_method :finish_or_reenqueue

    def self.finish_conversation(chat, agent)
      tag = "[ConversationRunner] chat_id=#{chat.id}"
      chat.reload
      chat.finish! if chat.may_finish?
      Rails.logger.info("#{tag} finished status=#{chat.task_status} step=#{chat.step_count}/#{agent.max_steps}")
      chat.broadcast_agent_status
      chat.broadcast_chat_cost
      notify_parent_of_completion(chat)
    end
    private_class_method :finish_conversation

    def self.notify_parent_of_completion(chat)
      return unless chat.parent_chat.present?

      agent = Daan::AgentRegistry.find(chat.agent_name)

      unless agent_reported_back?(chat)
        last_content = chat.messages.where(role: "assistant").last.content.truncate(500)
        Daan::CreateMessage.call(
          chat.parent_chat,
          role: "user",
          content: "[System] #{agent.display_name} completed their task without calling report_back. " \
                   "Their last message: #{last_content}",
          visible: false
        )
      end

      LlmJob.perform_later(chat.parent_chat)
    end
    private_class_method :notify_parent_of_completion

    def self.agent_reported_back?(chat)
      agent = Daan::AgentRegistry.find(chat.agent_name)
      last_task_message = chat.messages.where(role: "user").last
      return false unless last_task_message

      chat.parent_chat.messages
          .where(role: "user")
          .where_created_at_gt(last_task_message.created_at)
          .where_content_like("#{agent.display_name}: %")
          .exists?
    end
    private_class_method :agent_reported_back?

    def self.warn_approaching_step_limit(chat, remaining)
      return unless remaining == 3 && chat.parent_chat.present?

      chat.messages.create!(
        role: "user",
        content: "[System] You have 2 steps of work remaining before this thread is blocked. " \
                 "Call report_back now with your current findings.",
        visible: false
      )
    end
    private_class_method :warn_approaching_step_limit

    def self.notify_parent_of_termination(chat, status)
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
        content: "[System] #{agent.display_name}'s thread is now #{status}. " \
                 "#{reason} Their last message: #{last_content}",
        visible: false
      )

      LlmJob.perform_later(chat.parent_chat)
    end
    private_class_method :notify_parent_of_termination

    def self.already_responded?(chat)
      last_user_message      = chat.messages.where(role: "user").last
      last_assistant_message = chat.messages.where(role: "assistant").last
      return false unless last_user_message && last_assistant_message
      return false if last_assistant_message.context_user_message_id.nil?
      return false unless last_assistant_message.context_user_message_id >= last_user_message.id

      # If there's a tool result after the last assistant message, the conversation
      # is mid-flight (tool was called, result received, next step pending) — not done.
      !chat.messages.where(role: "tool").since_id(last_assistant_message.id).exists?
    end
    private_class_method :already_responded?

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
