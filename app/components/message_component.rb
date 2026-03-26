class MessageComponent < ViewComponent::Base
  include MarkdownHelper

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
    html = render_markdown(body)
    return rewrite_document_links(html).html_safe if return_to_uri.present?
    html
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
