module MarkdownHelper
  RENDERER = Redcarpet::Render::HTML.new(filter_html: true, hard_wrap: true, safe_links_only: true)
  MARKDOWN = Redcarpet::Markdown.new(RENDERER, fenced_code_blocks: true, autolink: true, tables: true, no_intra_emphasis: true)

  def render_markdown(text)
    # Ensure code fences are preceded by a blank line so hard_wrap doesn't
    # prevent Redcarpet from recognising them as block-level fences.
    content = text.to_s.gsub(/([^\n])\n(```)/m, "\\1\n\n\\2")
    MARKDOWN.render(content).html_safe
  end
end
