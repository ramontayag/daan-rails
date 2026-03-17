class ComposeBarComponentPreview < ViewComponent::Preview
  def default
    render ComposeBarComponent.new(action: "/messages")
  end

  def readonly
    render ComposeBarComponent.new(action: "/messages", readonly: true)
  end
end
