# lib/daan/core/delegate_task.rb
module Daan
  module Core
    class DelegateTask < RubyLLM::Tool
      extend ToolTimeout
      tool_timeout 10

      description "Delegate a task or follow-up message to a sub-agent. Each agent has one persistent thread — if a thread already exists, your message is added to it and the agent continues from where they left off. For follow-ups to an existing thread, keep the message brief; the agent already has the full context."
      param :agent_name, desc: "The agent to delegate to (e.g. 'engineering_manager', 'developer')"
      param :task,       desc: "The task or follow-up message. For initial delegation, include full context. For follow-ups to an existing thread, be brief — do not repeat what was already sent."

      def initialize(workspace: nil, chat: nil, storage: nil, agent_name: nil)
        @chat = chat
      end

      def execute(agent_name:, task:)
        current_agent = Daan::AgentRegistry.find(@chat.agent_name)
        unless current_agent.delegates_to.include?(agent_name)
          allowed = current_agent.delegates_to.join(", ")
          return "Error: #{@chat.agent_name} cannot delegate to #{agent_name}. Allowed: #{allowed}"
        end

        target_agent = Daan::AgentRegistry.find(agent_name)

        existing = @chat.sub_chats.exists?(agent_name: agent_name)
        sub_chat = @chat.sub_chats.find_or_create_by!(agent_name: agent_name)
        sub_chat.continue! if sub_chat.completed? || sub_chat.failed? || sub_chat.blocked?
        Daan::CreateMessage.call(sub_chat, role: "user", content: task)

        if existing
          "Sent follow-up to #{target_agent.display_name} in existing Thread ##{sub_chat.id}. Awaiting their response."
        else
          "Delegated to #{target_agent.display_name} (Thread ##{sub_chat.id}). Awaiting their report."
        end
      end
    end
  end
end
