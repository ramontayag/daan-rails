class ComposeBarComponent < ViewComponent::Base
  def initialize(action:, readonly: false, input_id: nil)
    @action   = action
    @readonly = readonly
    @input_id = input_id
  end

  private

  attr_reader :action, :readonly, :input_id
end
