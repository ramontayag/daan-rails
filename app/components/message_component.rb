class MessageComponent < ViewComponent::Base
  RENDERER = Redcarpet::Render::HTML.new(filter_html: true, hard_wrap: true, safe_links_only: true)
  MARKDOWN = Redcarpet::Markdown.new(RENDERER, fenced_code_blocks: true, autolink: true, tables: true)

  def initialize(role:, body:, dom_id: nil, sender_name: nil)
    @role        = role
    @body        = body
    @dom_id      = dom_id
    @sender_name = sender_name
  end

  private

  attr_reader :role, :body, :dom_id, :sender_name

  def rendered_body = MARKDOWN.render(body.to_s).html_safe

  def initials
    return "?" unless sender_name
    sender_name.split.first(2).map { |w| w[0] }.join.upcase
  end
end
