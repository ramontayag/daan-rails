# lib/daan/core/edit_agent.rb
module Daan
  module Core
    class EditAgent < RubyLLM::Tool
      description "Edit an existing agent configuration safely"
      param :agent_name, desc: "Name of the agent to edit"
      param :display_name, desc: "New display name (optional)", required: false
      param :description, desc: "New role/description (optional)", required: false
      param :tools, desc: "New tools array (optional - replaces existing tools)", required: false
      param :delegates_to, desc: "New delegates_to array (optional - replaces existing delegates)", required: false
      param :workspace, desc: "New workspace path (optional)", required: false
      param :model, desc: "New AI model (optional)", required: false
      param :max_turns, desc: "New max turns (optional)", required: false

      def initialize(workspace: nil, chat: nil, storage: nil, agent_name: nil)
        @workspace = workspace
      end

      def execute(agent_name:, display_name: nil, description: nil, tools: nil, delegates_to: nil, workspace: nil, model: nil, max_turns: nil)
        agent_file_path = Rails.root.join("lib/daan/core/agents/#{agent_name}.md")

        # Check if agent exists
        unless agent_file_path.exist?
          Rails.logger.error("EditAgent: Agent '#{agent_name}' does not exist")
          return "Error: Agent '#{agent_name}' does not exist at #{agent_file_path}"
        end

        # Parse existing agent file
        begin
          parsed = FrontMatterParser::Parser.parse_file(agent_file_path.to_s)
          existing_fm = parsed.front_matter
          existing_content = parsed.content
        rescue => e
          Rails.logger.error("EditAgent: Failed to parse existing agent file '#{agent_name}' - #{e.message}")
          return "Error parsing existing agent file: #{e.message}"
        end

        # Build updated frontmatter
        updated_fm = existing_fm.dup
        updated_fm["display_name"] = display_name if display_name
        updated_fm["model"] = model if model
        updated_fm["max_turns"] = max_turns if max_turns
        updated_fm["workspace"] = workspace if workspace

        # Handle tools array
        if tools
          tools = Array(tools)
          # Validate tools exist
          tools.each do |tool_name|
            begin
              Object.const_get(tool_name)
            rescue NameError
              Rails.logger.error("EditAgent: Tool class '#{tool_name}' does not exist")
              return "Error: Tool class '#{tool_name}' does not exist"
            end
          end
          updated_fm["tools"] = tools
        end

        # Handle delegates_to array
        if delegates_to
          delegates_to = Array(delegates_to)
          # Validate delegate agents exist
          delegates_to.each do |delegate_name|
            delegate_file = Rails.root.join("lib/daan/core/agents/#{delegate_name}.md")
            unless delegate_file.exist?
              Rails.logger.error("EditAgent: Delegate agent '#{delegate_name}' does not exist")
              return "Error: Delegate agent '#{delegate_name}' does not exist"
            end
          end
          updated_fm["delegates_to"] = delegates_to
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

        changes = []
        changes << "display_name" if display_name
        changes << "description" if description
        changes << "tools" if tools
        changes << "delegates_to" if delegates_to
        changes << "workspace" if workspace
        changes << "model" if model
        changes << "max_turns" if max_turns

        Rails.logger.info("EditAgent: Successfully updated agent '#{agent_name}' (changed: #{changes.join(', ')})")
        "Successfully updated agent '#{agent_name}' (changed: #{changes.join(', ')})"
      end
    end
  end
end