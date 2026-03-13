class AddCompactedMessageIdToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :compacted_message_id, :integer
    add_column :messages, :compacted_messages_count, :integer, default: 0, null: false
    add_index :messages, :compacted_message_id
    add_foreign_key :messages, :messages, column: :compacted_message_id
  end
end
