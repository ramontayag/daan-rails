# lib/daan/core/safe_execute.rb
module Daan
  module Core
    module SafeExecute
      def execute(...)
        super
      rescue => e
        "Error: #{e.message}"
      end
    end
  end
end
