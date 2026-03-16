# lib/daan/core/tool_timeout.rb
module Daan
  module Core
    module ToolTimeout
      def tool_timeout_seconds(seconds = nil)
        if seconds
          @tool_timeout_seconds = seconds
        else
          @tool_timeout_seconds
        end
      end
    end
  end
end
