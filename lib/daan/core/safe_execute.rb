# lib/daan/core/safe_execute.rb
module Daan
  module Core
    module SafeExecute
      DEFAULT_TIMEOUT_SECONDS = 10

      def execute(...)
        Timeout.timeout(tool_timeout) do
          super
        end
      rescue Timeout::Error
        "Error: timed out after #{tool_timeout}s"
      rescue => e
        "Error: #{e.message}"
      end

      private

      def tool_timeout
        self.class.tool_timeout || DEFAULT_TIMEOUT_SECONDS
      end
    end
  end
end
