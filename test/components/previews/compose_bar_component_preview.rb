class ComposeBarComponentPreview < ViewComponent::Preview
  def default
    render ComposeBarComponent.new(action: "/messages", autofocus: false)
  end

  def with_autofocus
    render ComposeBarComponent.new(action: "/messages", autofocus: true)
  end

  def readonly
    render ComposeBarComponent.new(action: "/messages", readonly: true)
  end
end
