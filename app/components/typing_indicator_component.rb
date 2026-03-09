# app/components/typing_indicator_component.rb
class TypingIndicatorComponent < ViewComponent::Base
  def initialize(typing:)
    @typing = typing
  end

  private

  attr_reader :typing
end
