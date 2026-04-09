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
    return raw_text if raw_text == "(empty)"
    render_markdown_preview(raw_text)
  end

  def render_markdown_preview(text)
    # First render markdown to HTML
    html = render_markdown(text)

    # Strip HTML tags for character counting to determine if truncation is needed
    plain_text = html.gsub(/<[^>]*>/, "")

    # Truncate at 150 characters if needed
    if plain_text.length > 150
      truncated = plain_text[0, 150]
      # Find the last complete word to avoid cutting in the middle
      truncated = truncated.gsub(/\s+\S*$/, "")
      # Re-render the truncated markdown from the original text
      truncated_markdown = text[0, truncated.length]
      html = render_markdown(truncated_markdown) + "…"
    end

    html.html_safe
  end

  def reply_count = [ chat.messages.size - 1, 0 ].max
  def timestamp   = chat.created_at.strftime("%b %d %H:%M")
end
