# lib/daan/agent.rb
module Daan
  Agent = Struct.new(:name, :display_name, :model_name, :system_prompt, :max_turns,
                     :workspace, :base_tools, :delegates_to, :allowed_commands,
                     keyword_init: true) do
    def initialize(**)
      super
      self.base_tools       ||= []
      self.delegates_to     ||= []
      self.allowed_commands ||= []
    end

    def tools(chat: nil)
      all_kwargs = { workspace: workspace, chat: chat, storage: Daan::Memory.storage,
                     agent_name: name, allowed_commands: allowed_commands }
      base_tools.map do |t|
        accepted = t.instance_method(:initialize).parameters.map(&:last)
        t.new(**all_kwargs.slice(*accepted))
      end
    end

    def to_param
      name
    end

    def busy?
      Chat.in_progress.exists?(agent_name: name)
    end

    def max_turns_reached?(turn_count)
      turn_count >= max_turns
    end
  end
end
