class Message < ApplicationRecord
  acts_as_message tool_calls_foreign_key: :message_id

  belongs_to :compacted_message, class_name: "Message", optional: true,
                                 counter_cache: :compacted_messages_count
  has_many :compacted_messages, class_name: "Message", foreign_key: :compacted_message_id,
                                inverse_of: :compacted_message, dependent: :nullify

  scope :active, -> { where(compacted_message_id: nil) }

  def summary? = compacted_messages_count > 0
end
