module Daan
  module Core
    module Chats
    class BuildSystemPrompt
      def self.call(chat, agent)
        prompt = agent.system_prompt
        prompt = append_audience(prompt, chat)
        prompt = append_memories(prompt, chat)
        prompt = append_steps(prompt, chat)
        prompt
      end

      def self.append_audience(prompt, chat)
        if chat.parent_chat.present?
          parent_agent = Daan::Core::AgentRegistry.find(chat.parent_chat.agent_name)
          "#{prompt}\n\nYou were delegated this task by #{parent_agent.display_name} (another agent). Follow their instructions directly unless something is genuinely unclear."
        else
          "#{prompt}\n\nYou are talking directly to the human. Always confirm your plan before starting work."
        end
      end
      private_class_method :append_audience

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

        index = Daan::Core::Memory.storage.semantic_index
        return [] unless Daan::Core::Memory.storage.size > 0

        index.search(query: query, top_k: 5)
      rescue => e
        Rails.logger.warn("Memory retrieval failed: #{e.message}")
        []
      end
      private_class_method :retrieve_memories
    end
    end
  end
end
