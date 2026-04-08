module Daan
  module Core
    module Chats
    class ForceReportBack
      SUMMARY_PROMPT = "#{Daan::Core::SystemTag::PREFIX} You have reached your step limit. " \
        "You will not be able to use any more tools. " \
        "Please summarize what you have accomplished and any findings so far."

      def self.call(chat)
        tag = "[ForceReportBack] chat_id=#{chat.id}"

        chat.messages.create!(role: "user", content: SUMMARY_PROMPT, visible: false)

        Rails.logger.info("#{tag} requesting forced summary (no tools)")
        response = chat.with_tools.step

        ar_message = chat.messages.where(role: "assistant").order(:id).last
        if ar_message
          Turbo::StreamsChannel.broadcast_append_to(
            "chat_#{chat.id}",
            target: "messages",
            renderable: ChatMessageComponent.new(message: ar_message, results: {})
          )
        end
        chat.broadcast_chat_cost
      end
    end
    end
  end
end
