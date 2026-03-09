# lib/daan/agent.rb
module Daan
  Agent = Struct.new(:name, :display_name, :model_name, :system_prompt, :max_turns,
                     :workspace, :base_tools, keyword_init: true) do
    def initialize(**)
      super
      self.base_tools ||= []
    end

    def tools
      @tools ||= base_tools.map do |tool_class|
        wp = workspace
        Class.new(tool_class) do
          @workspace = wp
          class << self; attr_reader :workspace; end
        end
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
