# lib/daan/core/hook_dispatch.rb
module Daan
  module Core
    module HookDispatch
      # Uses explicit **kwargs (not ...) so we can pass args: to hooks.
      # timeout_seconds is consumed by SafeExecute and not part of the tool's
      # own args, so we exclude it when forwarding to hooks.
      def execute(timeout_seconds: nil, **kwargs)
        active = Thread.current[:daan_active_hooks]
        if active
          tool_name = self.name
          active[:hooks].each do |h|
            next unless h.applies_to_tool?(tool_name)
            h.before_tool_call(chat: active[:chat], tool_name: tool_name, args: kwargs)
          rescue => e
            Rails.logger.error("[Hook] #{h.class} raised during before_tool_call: #{e.message}")
          end
        end

        result = super(timeout_seconds: timeout_seconds, **kwargs)

        if active
          tool_name = self.name
          active[:hooks].each do |h|
            next unless h.applies_to_tool?(tool_name)
            h.after_tool_call(chat: active[:chat], tool_name: tool_name, args: kwargs, result: result)
          rescue => e
            Rails.logger.error("[Hook] #{h.class} raised during after_tool_call: #{e.message}")
          end
        end

        result
      end
    end
  end
end
