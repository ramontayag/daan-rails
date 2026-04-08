module Daan
  module Core
    class CompactConversation
    KEEP_RECENT = 20

    SYSTEM_PROMPT = <<~PROMPT.strip
      Your task is to create a comprehensive summary of this conversation so that an agent
      can continue working with full context. Also save key learnings to shared memory
      using your memory tools — update existing entries if they conflict rather than
      creating duplicates.

      Structure your summary using this template:

      ## Goal
      [What task or goal was being pursued?]

      ## Instructions
      [What important instructions or constraints were established?]

      ## Discoveries
      [What notable things were learned during this conversation?]

      ## Accomplished
      [What work has been completed? What is still in progress or pending?]

      ## Key Context
      [Important facts, decisions, file paths, or references needed to continue]
    PROMPT

    def self.call(chat, agent, keep_recent: KEEP_RECENT)
      active = Message.active.where(chat_id: chat.id).order(:id).to_a
      to_compact = active[0..-(keep_recent + 1)]
      return if to_compact.blank?

      summary_text = generate_summary(to_compact, agent)
      summary = Daan::Core::CreateMessage.call(chat, role: "assistant", content: summary_text, broadcast_action: :prepend)
      Message.where(id: to_compact.map(&:id)).update_all(compacted_message_id: summary.id)
      # update_all bypasses callbacks so the counter cache needs a manual reset
      Message.reset_counters(summary.id, :compacted_messages)

      to_compact.each do |message|
        Turbo::StreamsChannel.broadcast_remove_to("chat_#{chat.id}", target: "message_#{message.id}")
      end

      summary
    end

    def self.generate_summary(messages, agent)
      storage = Daan::Core::Memory.storage
      memory_tools = [
        SwarmMemory::Tools::MemoryWrite.new(storage: storage, agent_name: agent.name),
        SwarmMemory::Tools::MemoryEdit.new(storage: storage, agent_name: agent.name)
      ]

      # Filter nil content (tool-call-only messages have no text to summarise)
      conversation_text = messages
        .select { |m| m.content.present? }
        .map { |m| "[#{m.role}]: #{m.content}" }
        .join("\n\n")

      RubyLLM.chat
        .with_model(agent.model_name)
        .with_instructions(SYSTEM_PROMPT)
        .with_tools(*memory_tools)
        .ask("Please summarize the following conversation:\n\n#{conversation_text}")
        .content
    end
    private_class_method :generate_summary
    end
  end
end
