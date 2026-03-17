class ComposeBarComponent < ViewComponent::Base
  def initialize(action:, readonly: false)
    @action   = action
    @readonly = readonly
  end

  private

  attr_reader :action, :readonly
end
