class PopoverComponent < ViewComponent::Base
  def initialize(trigger_text:, text_content: nil, html_content: nil, css_classes: "")
    @trigger_text = trigger_text
    @text_content = text_content
    @html_content = html_content
    @css_classes = css_classes
    @popover_id = "popover_#{SecureRandom.hex(8)}"
  end

  private

  attr_reader :trigger_text, :text_content, :html_content, :css_classes, :popover_id

  def display_content
    if html_content.present?
      html_content.html_safe
    else
      ERB::Util.h(text_content)
    end
  end
end
