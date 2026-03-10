module Perspective
  extend ActiveSupport::Concern

  included do
    helper_method :perspective_name
  end

  private

  def set_perspective
    name = params[:perspective].presence
    if name && name != "me"
      @perspective_agent = Daan::AgentRegistry.find(name)
      @perspective_name  = name
    else
      @perspective_agent = nil
      @perspective_name  = "me"
    end
  end

  def perspective_name = @perspective_name

  def default_url_options
    perspective_name == "me" ? {} : { perspective: perspective_name }
  end
end
