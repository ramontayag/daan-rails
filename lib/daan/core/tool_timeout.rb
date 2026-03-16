# lib/daan/core/tool_timeout.rb
module Daan
  module Core
    module ToolTimeout
      def tool_timeout(seconds = nil)
        if seconds
          @tool_timeout = seconds
        else
          @tool_timeout
        end
      end
    end
  end
end
