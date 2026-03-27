class ModalPageComponentPreview < ViewComponent::Preview
  def without_actions
    render ModalPageComponent.new(title: "Document Title", return_to_uri: "/") do
      tag.div("Body content goes here.", class: "p-6 text-sm text-gray-700")
    end
  end

  def with_actions
    render ModalPageComponent.new(title: "Scheduled Tasks", return_to_uri: "/") do |c|
      c.with_actions do
        tag.a("New task", href: "#",
              class: "px-3 py-1.5 bg-blue-600 text-white text-sm font-medium rounded hover:bg-blue-700")
      end

      tag.div("Body content goes here.", class: "p-6 text-sm text-gray-700")
    end
  end
end
