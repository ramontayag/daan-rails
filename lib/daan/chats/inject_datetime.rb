# lib/daan/chats/inject_datetime.rb
module Daan
  module Chats
    class InjectDatetime
      MARKER = "[System] Current datetime:"

      def self.call(chat)
        return if already_injected?(chat)

        now = Time.current
        content = "#{MARKER} #{now.strftime("%A, %B %-d, %Y at %H:%M %Z (UTC%:z)")}"

        # role: "user" (not "system") matches the convention used for all other
        # invisible injections in this codebase (ripple check, step limit warning, etc.).
        # visible: false keeps it out of the UI.
        chat.messages.create!(role: "user", content: content, visible: false)
      end

      def self.already_injected?(chat)
        chat.messages
            .where(role: "user", visible: false)
            .where(Message.arel_table[:content].matches("#{MARKER}%"))
            .exists?
      end
      private_class_method :already_injected?
    end
  end
end
