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
        ws = workspace
        Class.new(tool_class) do
          # Capture ws outside the block; inside Class.new, self is the new class.
          @workspace = ws
          class << self
            attr_reader :workspace
            # Anonymous classes have nil name; delegate to parent so RubyLLM
            # can derive the tool name for API calls.
            def name = superclass.name
            # RubyLLM stores tool metadata in class-level ivars (@description,
            # @parameters, etc.). These aren't inherited — each subclass gets
            # its own empty ivar. Explicitly delegate back to the parent class.
            def description(text = nil) = text ? super : superclass.description
            def parameters = superclass.parameters
            def params_schema_definition = superclass.params_schema_definition
            def provider_params = superclass.provider_params
          end
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
