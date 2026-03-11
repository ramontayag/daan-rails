# lib/daan/core/create_agent.rb
module Daan
  module Core
    class CreateAgent < RubyLLM::Tool
      description "Create a new agent definition file with configurable name, role, and tools"
      param :agent_name, desc: "Internal name for the agent (snake_case, e.g., 'data_analyst')"
      param :display_name, desc: "Human-readable display name (e.g., 'Data Analyst')"
      param :description, desc: "The agent's role and system prompt description"
      param :tools, desc: "Array of tool class names the agent should have (e.g., ['Daan::Core::Read', 'Daan::Core::Write'])"
      param :delegates_to, desc: "Array of agent names this agent can delegate to (optional, defaults to empty array)"
      param :workspace, desc: "Relative workspace path (optional, e.g., 'tmp/workspaces/data_analyst')"
      param :model, desc: "AI model to use (optional, defaults to 'claude-sonnet-4-20250514')"
      param :max_turns, desc: "Maximum conversation turns (optional, defaults to 10)"

      def initialize(workspace: nil, chat: nil)
        @workspace = workspace
      end

      def execute(agent_name:, display_name:, description:, tools:, delegates_to: [], workspace: nil, model: "claude-sonnet-4-20250514", max_turns: 10)
        # Validate agent name format
        unless agent_name.match?(/\A[a-z_]+\z/)
          return "Error: agent_name must be lowercase with underscores only (e.g., 'data_analyst')"
        end

        agent_file_path = Rails.root.join("lib/daan/core/agents/#{agent_name}.md")

        # Check if agent already exists
        if agent_file_path.exist?
          return "Error: Agent '#{agent_name}' already exists at #{agent_file_path}"
        end

        # Validate tools exist
        tools = Array(tools)
        tools.each do |tool_name|
          begin
            Object.const_get(tool_name)
          rescue NameError
            return "Error: Tool class '#{tool_name}' does not exist"
          end
        end

        # Validate delegate agents exist (if any)
        delegates_to = Array(delegates_to)
        delegates_to.each do |delegate_name|
          delegate_file = Rails.root.join("lib/daan/core/agents/#{delegate_name}.md")
          unless delegate_file.exist?
            return "Error: Delegate agent '#{delegate_name}' does not exist"
          end
        end

        # Create the agent file content
        frontmatter = {
          "name" => agent_name,
          "display_name" => display_name,
          "model" => model,
          "max_turns" => max_turns,
          "delegates_to" => delegates_to,
          "tools" => tools
        }

        # Add workspace if provided
        frontmatter["workspace"] = workspace if workspace

        frontmatter_yaml = frontmatter.to_yaml

        agent_content = <<~CONTENT
          #{frontmatter_yaml}---
          #{description.strip}
        CONTENT

        # Write the agent file
        agent_file_path.write(agent_content)

        # Create workspace directory if specified
        if workspace
          workspace_path = Rails.root.join(workspace)
          workspace_path.mkpath unless workspace_path.exist?
        end

        "Successfully created agent '#{agent_name}' (#{display_name}) at #{agent_file_path}"
      end
    end
  end
end