class ThreadListItemComponent < ViewComponent::Base
  include MarkdownHelper

  def initialize(chat:, open: false)
    @chat = chat
    @open = open
  end

  private

  attr_reader :chat, :open

  def preview_text
    raw_text = chat.messages.find { |m| m.role == "user" }&.content || "(empty)"
    truncate_text(render_markdown(raw_text), length: 150)
  end

  def truncate_text(text, length: 150)
    # Strip HTML tags for character counting while preserving rendered content
    plain_text = ActionController::Base.helpers.strip_tags(text)
    if plain_text.length > length
      truncated = plain_text[0...length]
      # Add back HTML rendering for the truncated text
      render_markdown(truncated).html_safe
    else
      text.html_safe
    end
  end

  def reply_count = [ chat.messages.size - 1, 0 ].max
  def timestamp   = chat.created_at.strftime("%b %d %H:%M")
end
