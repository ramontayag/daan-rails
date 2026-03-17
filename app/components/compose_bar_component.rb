class ComposeBarComponent < ViewComponent::Base
  def initialize(action:, readonly: false, autofocus: false)
    @action    = action
    @readonly  = readonly
    @autofocus = autofocus
  end

  private

  attr_reader :action, :readonly, :autofocus
end
