class Chat < ApplicationRecord
  include AASM

  acts_as_chat messages_foreign_key: :chat_id

  belongs_to :parent_chat, class_name: "Chat", optional: true
  has_many :sub_chats, class_name: "Chat", foreign_key: :parent_chat_id,
                       dependent: :nullify, inverse_of: :parent_chat

  validates :agent_name, presence: true

  aasm column: :task_status do
    state :pending, initial: true
    state :in_progress
    state :completed
    state :failed
    state :blocked

    event :start do
      transitions from: :pending, to: :in_progress
    end

    event :finish do
      transitions from: :in_progress, to: :completed
    end

    event :block do
      transitions from: :in_progress, to: :blocked
    end

    event :fail do
      transitions from: %i[pending in_progress], to: :failed
    end

    event :continue do
      transitions from: %i[completed blocked failed], to: :pending
    end
  end

  def self.conversation_partner_names_for(agent_name)
    my_chats = where(agent_name: agent_name)

    # Agents who delegated TO this agent (parents of this agent's chats)
    parent_names = where(id: my_chats.where.not(parent_chat_id: nil).select(:parent_chat_id))
                     .distinct.pluck(:agent_name)

    # Agents this agent delegated TO (children of this agent's chats)
    child_names = where(parent_chat: my_chats).distinct.pluck(:agent_name)

    (parent_names + child_names).uniq
  end

  def agent
    Daan::AgentRegistry.find(agent_name)
  end

  # Called explicitly by ConversationRunner after each AASM transition — not a callback.
  # See CLAUDE.md: broadcasts that render components belong in the caller.
  def broadcast_agent_status
    broadcast_replace_to(
      "agents",
      target: "agent_#{agent_name}",
      renderable: AgentItemComponent.new(agent: agent)
    )
  end
end
