class ThreadListComponent < ViewComponent::Base
  def initialize(agent:, chats:, open_chat: nil, readonly: false)
    @agent    = agent
    @chats    = chats
    @open_chat = open_chat
    @readonly  = readonly
  end

  private

  attr_reader :agent, :chats, :open_chat, :readonly
end
