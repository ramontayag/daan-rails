module Daan
  module Core
    class UpdateStep < RubyLLM::Tool
      extend ToolTimeout
      tool_timeout_seconds 10.seconds

      description "Update the status of a step in your checklist. " \
                  "Use the position number shown in your system prompt."
      param :position, desc: "Position number of the step to update"
      param :status, desc: "New status: pending, in_progress, or completed"

      def initialize(workspace: nil, chat: nil, storage: nil, agent_name: nil, allowed_commands: nil)
        @chat = chat
      end

      def execute(position:, status:)
        unless ChatStep::STATUSES.include?(status)
          return "Invalid status '#{status}'. Use: #{ChatStep::STATUSES.join(", ")}"
        end

        step = @chat.chat_steps.find_by(position: position)
        return "No step at position #{position}." unless step

        step.update!(status: status)
        broadcast_step_list

        "Step #{position} (#{step.title}) → #{status}"
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
