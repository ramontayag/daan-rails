class ModalPageComponent < ViewComponent::Base
  renders_one :actions

  def initialize(title:, return_to_uri:, **html_options)
    @title = title
    @return_to_uri = return_to_uri
    @html_options = html_options
  end

  private

  attr_reader :title, :return_to_uri

  def wrapper_html
    { class: "flex flex-col h-screen bg-white" }.merge(@html_options)
  end
end
