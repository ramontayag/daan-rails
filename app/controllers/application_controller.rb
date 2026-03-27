class ApplicationController < ActionController::Base
  rescue_from Daan::AgentNotFoundError, with: :agent_not_found

  private

  def agent_not_found
    head :not_found
  end

  def safe_return_uri(uri)
    return root_path unless uri.present?
    URI.parse(uri).path
  rescue URI::InvalidURIError
    root_path
  end
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes
end
