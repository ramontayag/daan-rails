module Daan
  module Core
    module Tool
      def self.included(_base)
        raise "Use `include Daan::Core::Tool.module(timeout:)` — plain include is not allowed"
      end

      def self.module(timeout:)
        t = timeout
        Module.new do
          define_singleton_method(:included) do |base|
            base.extend(Daan::Core::ToolTimeout)
            base.extend(Daan::Core::Tool::ClassMethods)
            base.tool_timeout_seconds(t)
          end
        end
      end

      module ClassMethods
        def tool_name
          new.name
        end
      end
    end
  end
end
