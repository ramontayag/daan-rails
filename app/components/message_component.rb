class MessageComponent < ViewComponent::Base
  def initialize(role:, body:, dom_id: nil)
    @role = role
    @body = body
    @dom_id = dom_id
  end

  private

  attr_reader :role, :body, :dom_id

  def alignment_classes = role == "user" ? "text-right" : "text-left"
  def bubble_classes = role == "user" ? "bg-blue-500 text-white" : "bg-gray-200 text-gray-900"
end
