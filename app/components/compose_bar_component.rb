class ComposeBarComponent < ViewComponent::Base
  def initialize(action:)
    @action = action
  end

  private

  attr_reader :action
end
