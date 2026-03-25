class MessageComponent < ViewComponent::Base
  RENDERER = Redcarpet::Render::HTML.new(filter_html: true, hard_wrap: true, safe_links_only: true)
  MARKDOWN = Redcarpet::Markdown.new(RENDERER, fenced_code_blocks: true, autolink: true, tables: true, no_intra_emphasis: true)

  def initialize(role: nil, body: nil, dom_id: nil, sender_name: nil, message: nil, return_to_uri: nil)
    @message      = message
    @role         = role || message&.role
    @body         = body || message&.content
    @dom_id       = dom_id
    @sender_name  = sender_name
    @return_to_uri = return_to_uri
  end

  private

  attr_reader :role, :body, :dom_id, :sender_name, :message, :return_to_uri

  def rendered_body
    # Ensure code fences are preceded by a blank line so hard_wrap doesn't
    # prevent Redcarpet from recognising them as block-level fences.
    content = body.to_s.gsub(/([^\n])\n(```)/m, "\\1\n\n\\2")
    html = MARKDOWN.render(content)
    html = rewrite_document_links(html) if return_to_uri.present?
    html.html_safe
  end

  def rewrite_document_links(html)
    escaped = Rack::Utils.escape(return_to_uri)
    html.gsub(%r{href="(?:(?:https?://[^/"]+)?/documents/(\d+))"}) do
      %(href="/documents/#{$1}?return_to_uri=#{escaped}" data-turbo-frame="_top")
    end
  end

  def initials
    return "?" unless sender_name
    sender_name.split.first(2).map { |w| w[0] }.join.upcase
  end
end
