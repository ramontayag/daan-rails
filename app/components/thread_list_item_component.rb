class ThreadListItemComponent < ViewComponent::Base
  def initialize(chat:, open: false)
    @chat = chat
    @open = open
  end

  private

  attr_reader :chat, :open

  def preview_text
    chat.messages.find { |m| m.role == "user" }&.content || "(empty)"
  end

  def reply_count = [ chat.messages.size - 1, 0 ].max
  def timestamp   = chat.created_at.strftime("%b %d %H:%M")
end
