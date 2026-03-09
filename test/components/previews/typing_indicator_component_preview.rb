# test/components/previews/typing_indicator_component_preview.rb
class TypingIndicatorComponentPreview < ViewComponent::Preview
  def typing
    render TypingIndicatorComponent.new(typing: true)
  end

  def idle
    render TypingIndicatorComponent.new(typing: false)
  end
end
