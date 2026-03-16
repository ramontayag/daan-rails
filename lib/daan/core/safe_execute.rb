# lib/daan/core/safe_execute.rb
module Daan
  module Core
    module SafeExecute
      DEFAULT_TIMEOUT_SECONDS = 10

      def execute(...)
        Timeout.timeout(tool_timeout_seconds) do
          super
        end
      rescue Timeout::Error
        "Error: timed out after #{tool_timeout_seconds}s"
      rescue => e
        "Error: #{e.message}"
      end

      private

      def tool_timeout_seconds
        self.class.tool_timeout_seconds || DEFAULT_TIMEOUT_SECONDS
      end
    end
  end
end
