# lib/daan/core/delegate_task.rb
module Daan
  module Core
    class DelegateTask < RubyLLM::Tool
      description "Delegate a task to a sub-agent"
      param :agent_name, desc: "The agent to delegate to (e.g. 'engineering_manager', 'developer')"
      param :task,       desc: "The task description to assign"

      def initialize(workspace: nil, chat: nil, storage: nil)
        @chat = chat
      end

      def execute(agent_name:, task:)
        current_agent = Daan::AgentRegistry.find(@chat.agent_name)
        unless current_agent.delegates_to.include?(agent_name)
          allowed = current_agent.delegates_to.join(", ")
          return "Error: #{@chat.agent_name} cannot delegate to #{agent_name}. Allowed: #{allowed}"
        end

        target_agent = Daan::AgentRegistry.find(agent_name)

        sub_chat = Chat.create!(agent_name: agent_name, parent_chat: @chat)
        Daan::CreateMessage.call(sub_chat, role: "user", content: task)

        "Delegated to #{target_agent.display_name} (Thread ##{sub_chat.id}). Awaiting their report."
      end
    end
  end
end
