# lib/daan/agent.rb
module Daan
  Agent = Struct.new(:name, :display_name, :model_name, :system_prompt, :max_turns,
                     :workspace, :base_tools, :delegates_to, keyword_init: true) do
    def initialize(**)
      super
      self.base_tools ||= []
      self.delegates_to ||= []
    end

    def tools(chat: nil)
      base_tools.map { |t| t.new(workspace: workspace, chat: chat, storage: Daan::Memory.storage) }
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
