class MessageComponent < ViewComponent::Base
  RENDERER = Redcarpet::Render::HTML.new(filter_html: true, hard_wrap: true, safe_links_only: true)
  MARKDOWN = Redcarpet::Markdown.new(RENDERER, fenced_code_blocks: true, autolink: true, tables: true)

  def initialize(role:, body:, dom_id: nil)
    @role = role
    @body = body
    @dom_id = dom_id
  end

  private

  attr_reader :role, :body, :dom_id

  def alignment_classes = role == "user" ? "text-right" : "text-left"
  def bubble_classes = role == "user" ? "bg-blue-500 text-white" : "bg-gray-200 text-gray-900"
  def prose_classes = role == "user" ? "prose prose-sm prose-invert" : "prose prose-sm"

  def rendered_body = MARKDOWN.render(body).html_safe
end
