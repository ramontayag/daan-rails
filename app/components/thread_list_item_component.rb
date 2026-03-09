class ThreadListItemComponent < ViewComponent::Base
  def initialize(chat:)
    @chat = chat
  end

  private

  attr_reader :chat

  def preview_text
    chat.messages.find { |m| m.role == "user" }&.content&.truncate(80) || "(empty)"
  end

  def reply_count = [chat.messages.size - 1, 0].max
  def timestamp   = chat.created_at.strftime("%b %d %H:%M")
end
