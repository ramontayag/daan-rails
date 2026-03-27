module Daan
  module Core
    class ScheduleTask < RubyLLM::Tool
      include Daan::Core::Tool.module(timeout: 10.seconds)

      description "Schedule a one-shot task to fire a message to an agent at a future time. " \
                  "The agent will receive the message as a new conversation thread. " \
                  "Use this for deferred follow-ups such as 'check CI in 5 minutes' or " \
                  "'remind the team about the standup tomorrow morning'."

      param :agent_name, desc: "The agent who should receive the message (e.g. 'chief_of_staff', 'developer')"
      param :message,    desc: "The message to send to the agent when the task fires"
      param :run_at,     desc: "When to fire the task, as an ISO8601 datetime string (e.g. '2026-03-27T09:00:00+01:00')"

      def initialize(chat: nil, **)
        @chat = chat
      end

      def execute(agent_name:, message:, run_at:)
        Daan::AgentRegistry.find(agent_name)

        parsed_run_at = begin
          Time.iso8601(run_at)
        rescue ArgumentError, TypeError
          return "Error: '#{run_at}' is not a valid ISO8601 datetime string."
        end

        task = ScheduledTask.create!(
          agent_name:     agent_name,
          message:        message,
          task_type:      :one_shot,
          run_at:         parsed_run_at,
          source_chat_id: @chat&.id,
          enabled:        true
        )

        "Scheduled task ##{task.id} created. Agent '#{agent_name}' will receive the message at #{parsed_run_at.iso8601}."
      rescue Daan::AgentNotFoundError
        "Error: agent '#{agent_name}' not found in the registry."
      end
    end
  end
end
