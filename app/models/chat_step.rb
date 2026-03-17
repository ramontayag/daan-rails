class ChatStep < ApplicationRecord
  STATUSES = %w[pending in_progress completed].freeze

  belongs_to :chat

  validates :title, presence: true
  validates :position, presence: true, uniqueness: { scope: :chat_id }
  validates :status, inclusion: { in: STATUSES }
end
