module Daan
  module Core
    module Hook
      module InstanceMethods
        # Default no-op lifecycle methods. Hook classes override what they need.
        def before_llm_call(chat:, last_tool_calls:); end
        def before_conversation(chat:); end
        def before_tool_call(chat:, tool_name:, args:); end
        def after_tool_call(chat:, tool_name:, args:, result:); end
        def after_conversation(chat:, status:); end

        # Returns true if this hook applies to the given tool name.
        # Agent hooks (plain include) always return false — they are not tool hooks.
        def applies_to_tool?(tool_name)
          tool_classes = self.class.instance_variable_get(:@applies_to_tool_classes)
          return false unless tool_classes
          tool_classes.any? { |klass| klass.tool_name == tool_name }
        end
      end

      # Agent hooks: plain include. No configuration needed.
      def self.included(base)
        Registry.register(base)
        base.include(InstanceMethods)
      end

      # Tool hooks: .module(applies_to: [ToolClass, ...]).
      # Uses class references — applies_to_tool? compares via .tool_name.
      def self.module(applies_to:)
        tool_classes = applies_to
        Module.new do
          define_singleton_method(:included) do |base|
            Daan::Core::Hook::Registry.register(base)
            base.instance_variable_set(:@applies_to_tool_classes, tool_classes)
            base.include(Daan::Core::Hook::InstanceMethods)
          end
        end
      end

      class Registry
        @registry = []

        class << self
          def register(klass)
            @registry << klass unless @registry.include?(klass)
          end

          # Resolve full Ruby constant name strings to fresh instances.
          # "Daan::Core::Shaping" => Object.const_get("Daan::Core::Shaping").new
          def agent_hooks(names)
            names.map { |name| Object.const_get(name).new }
          end

          # Returns instances of tool hooks (included via .module(applies_to:)).
          # Empty in Slice 1; populated in Slice 2.
          def tool_hooks
            @registry
              .select { |klass| klass.instance_variable_defined?(:@applies_to_tool_classes) }
              .map(&:new)
          end

          def all
            @registry.dup
          end

          def clear
            @registry = []
          end
        end
      end
    end
  end
end
