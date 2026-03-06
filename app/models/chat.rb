class Chat < ApplicationRecord
  include AASM

  acts_as_chat messages_foreign_key: :chat_id

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
  end

  # TODO: AgentRegistry must be seeded at boot (Task 4: Agent Definition Loader)
  #       before any Chat can call #agent — raises KeyError otherwise.
  def agent
    Daan::AgentRegistry.find(agent_name)
  end

  def max_turns_reached?
    agent.max_turns_reached?(turn_count)
  end
end
