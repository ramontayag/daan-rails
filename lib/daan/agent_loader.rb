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

      base_dir = Pathname(file_path).dirname
      system_prompt = resolve_includes(parsed.content.strip, base_dir)
      if workspace
        system_prompt += "\n\n" + workspace_instructions(workspace)
      end

      {
        name:          fm.fetch("name"),
        display_name:  fm.fetch("display_name"),
        model_name:    fm.fetch("model"),
        max_steps:     fm.fetch("max_steps"),
        system_prompt: system_prompt,
        base_tools:    base_tools,
        workspace:     workspace,
        delegates_to:     fm.fetch("delegates_to", []),
        hook_names:       fm.fetch("hooks", []),
        allowed_commands: fm["allowed_commands"]
      }
    end

    def self.resolve_includes(content, base_dir)
      content.gsub(/\{\{include:\s*(.+?)\}\}/) do
        base_dir.join($1.strip).read.strip
      end
    end

    def self.workspace_instructions(workspace)
      lines = []
      lines << "Your workspace is at #{workspace.root}. It is yours alone — no other agent shares it. All file operations (Read, Write, Bash) are scoped to this directory — paths outside it will be rejected. Use relative paths or paths under #{workspace.root}."
      lines << "You are responsible for keeping it orderly: decide where repos, projects, and temporary files live, and stick to that structure."
      lines << "Use #{SwarmMemory::Tools::MemoryWrite.name.demodulize} to record where you put things (repos, projects, temp files) so you can find them again without re-exploring. When starting a task, check memory first — you may have worked in this workspace before and know exactly where things are."

      if (self_repo = ENV["DAAN_SELF_REPO"].presence)
        lines << "The team you are part of lives at #{self_repo}. When asked to modify the team — add or change agents, tools, or behaviour — clone that repo, make your changes on a branch, and open a pull request."
      end

      lines.join("\n\n")
    end

    def self.sync!(directory)
      Dir.glob(Pathname(directory).join("*.md")).each do |file_path|
        definition = parse(file_path)
        AgentRegistry.register(Agent.new(**definition))
      end
    end
  end
end
