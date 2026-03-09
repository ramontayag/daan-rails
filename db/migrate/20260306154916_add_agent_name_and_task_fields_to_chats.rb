class AddAgentNameAndTaskFieldsToChats < ActiveRecord::Migration[8.1]
  def change
    add_column :chats, :agent_name, :string, null: false
    add_column :chats, :task_status, :string, null: false, default: "pending"
    add_column :chats, :turn_count, :integer, null: false, default: 0
    add_index :chats, :agent_name
  end
end
