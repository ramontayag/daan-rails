class Message < ApplicationRecord
  acts_as_message tool_calls_foreign_key: :message_id

  belongs_to :compacted_message, class_name: "Message", optional: true,
                                 counter_cache: :compacted_messages_count
  has_many :compacted_messages, class_name: "Message", foreign_key: :compacted_message_id,
                                inverse_of: :compacted_message, dependent: :nullify

  scope :active, -> { where(compacted_message_id: nil) }
  scope :assistant, -> { where(role: "assistant") }
  scope :since_id, ->(id) { where(Message.arel_table[:id].gt(id)) }
  scope :where_created_at_gt, ->(time) { where(Message.arel_table[:created_at].gt(time)) }
  scope :where_content_like, ->(pattern) { where(Message.arel_table[:content].matches(pattern)) }

  def summary? = compacted_messages_count > 0

  def to_llm
    return super unless role == "user" && visible?

    msg = super
    msg.content = "[Sent at: #{created_at.iso8601}]\n\n#{msg.content}"
    msg
  end
end
