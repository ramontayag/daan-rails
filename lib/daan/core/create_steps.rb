module Daan
  module Core
    class CreateSteps < RubyLLM::Tool
      extend ToolTimeout
      tool_timeout_seconds 10.seconds

      description "Create a checklist of steps for the current task. " \
                  "Use this at the start of a task to plan your work. " \
                  "Steps appear in your system prompt so you always see them."
      param :steps, type: "array", desc: "Ordered list of step titles"

      def initialize(workspace: nil, chat: nil, storage: nil, agent_name: nil, allowed_commands: nil)
        @chat = chat
      end

      def execute(steps:)
        return "Provide at least one step." if steps.empty?

        max_pos = @chat.chat_steps.maximum(:position) || 0
        created = steps.each_with_index.map do |title, i|
          @chat.chat_steps.create!(title: title, position: max_pos + i + 1)
        end

        broadcast_step_list

        created.map { |s| "#{s.position}. [ ] #{s.title}" }.join("\n")
      end

      private

      def broadcast_step_list
        @chat.reload
        Turbo::StreamsChannel.broadcast_replace_to(
          "chat_#{@chat.id}",
          target: "chat_step_list",
          renderable: ChatStepListComponent.new(chat: @chat)
        )
      end
    end
  end
end
