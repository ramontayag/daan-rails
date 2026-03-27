# lib/daan/core/hooks/audit_log.rb
module Daan
  module Core
    module Hooks
      class AuditLog
        include Daan::Core::Hook.module(applies_to: [ Daan::Core::Bash, Daan::Core::Write ])

        def before_tool_call(chat:, tool_name:, args:)
          Rails.logger.info("[AuditLog] before_tool_call chat_id=#{chat.id} tool=#{tool_name}")
        end

        def after_tool_call(chat:, tool_name:, args:, result:)
          preview = result.to_s.truncate(120)
          Rails.logger.info("[AuditLog] after_tool_call chat_id=#{chat.id} tool=#{tool_name} result=#{preview}")
        end
      end
    end
  end
end
