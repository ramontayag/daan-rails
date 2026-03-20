class ChatHeaderStatsComponent < ViewComponent::Base
  def initialize(chat:)
    @chat = chat
  end

  private

  attr_reader :chat
end
