# app/controllers/documents_controller.rb
class DocumentsController < ApplicationController
  def show
    @document = Document.find(params[:id])
    renderer = Redcarpet::Render::HTML.new(hard_wrap: true)
    markdown = Redcarpet::Markdown.new(renderer,
      fenced_code_blocks: true,
      autolink: true,
      tables: true,
      strikethrough: true
    )
    @body_html = markdown.render(@document.body.to_s)
    @return_to_uri = safe_return_uri(params[:return_to_uri])
  end

  private

  def safe_return_uri(uri)
    return root_path unless uri.present?
    URI.parse(uri).path
  rescue URI::InvalidURIError
    root_path
  end
end
