# app/components/chat_cost_component.rb
class ChatCostComponent < ViewComponent::Base
  def initialize(chat:)
    @chat = chat
  end

  private

  attr_reader :chat
end
