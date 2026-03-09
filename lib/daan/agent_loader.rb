# lib/daan/agent_loader.rb
module Daan
  class AgentLoader
    def self.parse(file_path)
      parsed = FrontMatterParser::Parser.parse_file(file_path.to_s)
      fm = parsed.front_matter

      tool_names = fm.fetch("tools", [])
      base_tools = tool_names.map { |name| Object.const_get(name) }

      workspace_rel = fm["workspace"]
      workspace = workspace_rel ? Workspace.new(Rails.root.join(workspace_rel)) : nil

      {
        name:          fm.fetch("name"),
        display_name:  fm.fetch("display_name"),
        model_name:    fm.fetch("model"),
        max_turns:     fm.fetch("max_turns"),
        system_prompt: parsed.content.strip,
        base_tools:    base_tools,
        workspace:     workspace
      }
    rescue => e
      raise "Invalid agent definition at #{file_path}: #{e.message}"
    end

    def self.sync!(directory)
      Dir.glob(Pathname(directory).join("*.md")).each do |file_path|
        definition = parse(file_path)
        AgentRegistry.register(Agent.new(**definition))
      end
    end
  end
end
