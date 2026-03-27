# app/controllers/documents_controller.rb
class DocumentsController < ApplicationController
  def show
    @document = Document.find(params[:id])
    @return_to_uri = safe_return_uri(params[:return_to_uri])

    respond_to do |format|
      format.html { @body_html = helpers.render_markdown(@document.body.to_s) }
      format.md do
        filename = "#{@document.title.parameterize}.md"
        send_data @document.body, filename: filename, type: "text/markdown", disposition: "attachment"
      end
    end
  end

  private
end
