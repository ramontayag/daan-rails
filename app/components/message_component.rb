class MessageComponent < ViewComponent::Base
  RENDERER = Redcarpet::Render::HTML.new(filter_html: true, hard_wrap: true, safe_links_only: true)
  MARKDOWN = Redcarpet::Markdown.new(RENDERER, fenced_code_blocks: true, autolink: true, tables: true)

  def initialize(role:, body:, dom_id: nil, viewer_is_agent: false)
    @role            = role
    @body            = body
    @dom_id          = dom_id
    @viewer_is_agent = viewer_is_agent
  end

  private

  attr_reader :role, :body, :dom_id, :viewer_is_agent

  def self_message?
    viewer_is_agent ? role == "assistant" : role == "user"
  end

  def alignment_classes = self_message? ? "text-right" : "text-left"
  def bubble_classes    = self_message? ? "bg-blue-500 text-white" : "bg-gray-200 text-gray-900"
  def prose_classes     = self_message? ? "prose prose-sm prose-invert" : "prose prose-sm"

  def rendered_body = MARKDOWN.render(body.to_s).html_safe
end
