# lib/daan/agent_registry.rb
module Daan
  class AgentNotFoundError < StandardError; end

  class AgentRegistry
    @registry = {}

    class << self
      def register(agent)
        @registry[agent.name] = agent
      end

      def find(name)
        @registry.fetch(name) { raise AgentNotFoundError, "No agent registered: #{name.inspect}" }
      end

      def all
        @registry.values
      end

      def clear
        @registry = {}
      end
    end
  end
end
