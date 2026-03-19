class DropTurnCountFromChats < ActiveRecord::Migration[8.1]
  def change
    remove_column :chats, :turn_count, :integer, default: 0, null: false
  end
end
