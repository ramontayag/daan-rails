# lib/daan/core/edit_agent.rb
module Daan
  module Core
    class EditAgent < RubyLLM::Tool
      extend ToolTimeout
      tool_timeout_seconds 10.seconds

      description "Edit an existing agent configuration safely"
      param :agent_name, desc: "Name of the agent to edit"
      param :display_name, desc: "New display name (optional)"
      param :description, desc: "New role/description (optional)"
      param :tools, desc: "New tools array (optional - replaces existing tools)"
      param :delegates_to, desc: "New delegates_to array (optional - replaces existing delegates)"
      param :workspace, desc: "New workspace path (optional)"
      param :model, desc: "New AI model (optional)"
      param :max_steps, desc: "New max turns (optional)"

      def initialize(workspace: nil, chat: nil, agents_dir: nil)
        @workspace = workspace
        @agents_dir = agents_dir || Rails.root.join("lib/daan/core/agents")
      end

      def execute(agent_name:, display_name: nil, description: nil, tools: nil, delegates_to: nil, workspace: nil, model: nil, max_steps: nil)
        agent_file_path = @agents_dir.join("#{agent_name}.md")

        # Check if agent exists
        unless agent_file_path.exist?
          return "Error: Agent '#{agent_name}' does not exist at #{agent_file_path}"
        end

        # Parse existing agent file
        begin
          parsed = FrontMatterParser::Parser.parse_file(agent_file_path.to_s)
          existing_fm = parsed.front_matter
          existing_content = parsed.content
          if existing_fm["name"].nil?
            return "Error: Failed to parse existing agent file: missing required frontmatter"
          end
        rescue => e
          return "Error: Failed to parse existing agent file: #{e.message}"
        end

        # Build updated frontmatter
        updated_fm = existing_fm.dup
        updated_fm["display_name"] = display_name if display_name
        updated_fm["model"] = model if model
        updated_fm["max_steps"] = max_steps if max_steps
        if workspace
          workspace.empty? ? updated_fm.delete("workspace") : updated_fm["workspace"] = workspace
        end

        # Handle tools array
        if tools
          tools = Array(tools)
          if tools.empty?
            updated_fm.delete("tools")
          else
            tools.each do |tool_name|
              begin
                Object.const_get(tool_name)
              rescue NameError
                return "Error: Tool class '#{tool_name}' does not exist"
              end
            end
            updated_fm["tools"] = tools
          end
        end

        # Handle delegates_to array
        if delegates_to
          delegates_to = Array(delegates_to)
          if delegates_to.empty?
            updated_fm.delete("delegates_to")
          else
            delegates_to.each do |delegate_name|
              delegate_file = @agents_dir.join("#{delegate_name}.md")
              unless delegate_file.exist?
                return "Error: Delegate agent '#{delegate_name}' does not exist"
              end
            end
            updated_fm["delegates_to"] = delegates_to
          end
        end

        # Use new description or keep existing
        content_to_use = description ? description.strip : existing_content.strip

        # Create updated content
        frontmatter_yaml = updated_fm.to_yaml
        updated_content = <<~CONTENT
          #{frontmatter_yaml}---
          #{content_to_use}
        CONTENT

        # Write the updated agent file
        agent_file_path.write(updated_content)

        # Handle workspace directory creation/cleanup
        if workspace
          new_workspace_path = Rails.root.join(workspace)
          new_workspace_path.mkpath unless new_workspace_path.exist?

          # Clean up old workspace if it was different and empty
          old_workspace = existing_fm["workspace"]
          if old_workspace && old_workspace != workspace
            old_workspace_path = Rails.root.join(old_workspace)
            if old_workspace_path.exist? && old_workspace_path.children.empty?
              old_workspace_path.rmdir rescue nil # Ignore errors
            end
          end
        end

        # Update the registry with the new definition
        begin
          definition = Daan::AgentLoader.parse(agent_file_path)
          agent = Daan::Agent.new(**definition)
          Daan::AgentRegistry.register(agent)
        rescue => e
          return "Error: Failed to register updated agent - #{e.message}"
        end

        changes = []
        changes << "display_name" if display_name
        changes << "description" if description
        changes << "tools" if tools
        changes << "delegates_to" if delegates_to
        changes << "workspace" if workspace
        changes << "model" if model
        changes << "max_steps" if max_steps

        "Successfully updated agent '#{agent_name}' (changed: #{changes.join(', ')})"
      end
    end
  end
end
