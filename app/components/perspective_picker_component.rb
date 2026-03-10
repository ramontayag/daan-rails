class PerspectivePickerComponent < ViewComponent::Base
  def initialize(current_perspective:)
    @current_perspective = current_perspective
  end

  private

  attr_reader :current_perspective

  def agents
    Daan::AgentRegistry.all
  end
end
