# lib/daan/core/safe_execute.rb
module Daan
  module Core
    module SafeExecute
      DEFAULT_TIMEOUT_SECONDS = 10.seconds
      MAX_TIMEOUT_SECONDS = 30.minutes

      def params_schema
        schema = super || { "type" => "object", "properties" => {}, "required" => [] }
        schema = schema.deep_dup
        schema["properties"] ||= {}
        default = (class_timeout || DEFAULT_TIMEOUT_SECONDS).to_i
        schema["properties"]["timeout_seconds"] = {
          "type" => "number",
          "description" => "Override execution timeout in seconds (default: #{default}, max: #{MAX_TIMEOUT_SECONDS.to_i})"
        }
        schema
      end

      def execute(timeout_seconds: nil, **kwargs)
        effective = resolve_timeout(timeout_seconds)
        Timeout.timeout(effective) do
          super(**kwargs)
        end
      rescue Timeout::Error
        "Error: timed out after #{effective}s"
      rescue => e
        "Error: #{e.message}"
      end

      private

      def class_timeout
        klass = self.class
        klass.respond_to?(:tool_timeout_seconds) ? klass.tool_timeout_seconds : nil
      end

      def resolve_timeout(requested)
        max = MAX_TIMEOUT_SECONDS.to_i
        default = (class_timeout || DEFAULT_TIMEOUT_SECONDS).to_f
        return default unless requested

        requested = requested.to_f
        if requested > max
          raise "timeout_seconds #{requested.to_i} exceeds maximum of #{max}"
        end
        requested
      end
    end
  end
end
