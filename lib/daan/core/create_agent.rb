# lib/daan/core/create_agent.rb
module Daan
  module Core
    class CreateAgent < RubyLLM::Tool
      include Daan::Core::Tool.module(timeout: 10.seconds)

      description "Create a new agent configuration file"
      param :agent_name, desc: "The internal name for the agent (e.g., 'data_analyst')"
      param :display_name, desc: "The human-readable display name (e.g., 'Data Analyst')"
      param :description, desc: "The agent's role and capabilities description"
      param :tools, desc: "Array of tool class names the agent can use (optional)", required: false
      param :delegates_to, desc: "Array of agent names this agent can delegate to (optional)", required: false
      param :workspace, desc: "Relative workspace path for the agent (optional)", required: false
      param :model, desc: "AI model to use (optional, defaults to claude-sonnet-4-20250514)", required: false
      param :max_steps, desc: "Maximum conversation turns (optional, defaults to 10)", required: false

      def initialize(workspace: nil, chat: nil, agents_dir: nil)
        @chat = chat
        @agents_dir = agents_dir || Rails.root.join("lib/daan/core/agents")
      end

      def execute(agent_name:, display_name:, description:, tools: nil, delegates_to: nil, workspace: nil, model: nil, max_steps: nil)
        # Validate agent_name format
        unless agent_name.match?(/\A[a-z][a-z0-9_]*\z/)
          return "Error: agent_name must start with a lowercase letter and contain only lowercase letters, numbers, and underscores"
        end

        # Check if agent already exists
        agents_dir = @agents_dir
        agent_file = agents_dir.join("#{agent_name}.md")

        if agent_file.exist?
          return "Error: Agent '#{agent_name}' already exists"
        end

        # Set defaults
        model ||= "claude-sonnet-4-20250514"
        max_steps ||= 10
        tools ||= []
        delegates_to ||= []

        # Validate tool names exist
        tools.each do |tool_name|
          begin
            Object.const_get(tool_name)
          rescue NameError
            return "Error: Tool class '#{tool_name}' does not exist"
          end
        end

        # Validate delegate agents exist (only check if not empty)
        unless delegates_to.empty?
          delegates_to.each do |delegate_name|
            delegate_file = agents_dir.join("#{delegate_name}.md")
            unless delegate_file.exist?
              return "Error: Delegate agent '#{delegate_name}' does not exist"
            end
          end
        end

        # Build frontmatter
        frontmatter = {
          "name" => agent_name,
          "display_name" => display_name,
          "model" => model,
          "max_steps" => max_steps
        }

        frontmatter["workspace"] = workspace if workspace
        frontmatter["delegates_to"] = delegates_to unless delegates_to.empty?
        frontmatter["tools"] = tools unless tools.empty?

        # Build file content
        content = +"---\n"
        frontmatter.each do |key, value|
          if value.is_a?(Array)
            content << "#{key}:\n"
            value.each { |item| content << "  - #{item}\n" }
          else
            content << "#{key}: #{value}\n"
          end
        end
        content << "---\n"
        content << description

        # Write the file
        agent_file.write(content)

        # Reload the agent registry to include the new agent
        begin
          definition = Daan::Core::AgentLoader.parse(agent_file)
          agent = Daan::Core::Agent.new(**definition)
          Daan::Core::AgentRegistry.register(agent)

          "Successfully created agent '#{agent_name}' (#{display_name})"
        rescue => e
          # If there's an error registering, clean up the file
          agent_file.delete if agent_file.exist?
          "Error: Failed to register agent - #{e.message}"
        end
      end
    end
  end
end
