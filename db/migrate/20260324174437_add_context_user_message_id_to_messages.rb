class AddContextUserMessageIdToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :context_user_message_id, :integer
  end
end
