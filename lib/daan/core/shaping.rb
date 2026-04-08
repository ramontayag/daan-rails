module Daan
  module Core
    class Shaping
      include Daan::Core::Hook

      RIPPLE_CHECK_CONTENT = "#{Daan::Core::SystemTag::PREFIX} Ripple check: you updated document(s) in the previous turn. " \
        "Verify your changes are consistent with related documents " \
        "(shaping → slices → slice plans) before continuing."

      def before_llm_call(chat:, last_tool_calls:)
        return unless last_tool_calls.any? { |tc| tc.name == Daan::Core::UpdateDocument.tool_name }

        # Use chat.messages.create! directly — NOT Daan::Core::CreateMessage.
        # CreateMessage enqueues LlmJob for user-role messages, which would
        # trigger a recursive job mid-conversation.
        chat.messages.create!(role: "user", content: RIPPLE_CHECK_CONTENT, visible: false)
      end
    end
  end
end
