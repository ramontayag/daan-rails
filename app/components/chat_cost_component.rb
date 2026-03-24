# app/components/chat_cost_component.rb
class ChatCostComponent < ViewComponent::Base
  def initialize(chat:)
    @chat = chat
  end

  private

  attr_reader :chat

  def sub_chats
    @sub_chats ||= chat.sub_chats.to_a
  end

  def has_sub_chats?
    sub_chats.any?
  end
end
