# lib/daan/core/list_agents.rb
module Daan
  module Core
    class ListAgents < RubyLLM::Tool
      include Daan::Core::Tool.module(timeout: 10.seconds)

      description "List all registered agents on the team — their names, descriptions, and tools. " \
                  "Use this to understand who is available and what each agent can do before delegating."

      def initialize(workspace: nil, chat: nil, storage: nil, agent_name: nil)
      end

      def execute
        agents = Daan::AgentRegistry.all
        return "No agents are currently registered." if agents.empty?

        agents.map do |agent|
          tools = agent.base_tools.map(&:name).join(", ")
          tools_line = tools.empty? ? "" : "\n  Tools: #{tools}"
          "#{agent.display_name} (#{agent.name})#{tools_line}"
        end.join("\n\n")
      end
    end
  end
end
