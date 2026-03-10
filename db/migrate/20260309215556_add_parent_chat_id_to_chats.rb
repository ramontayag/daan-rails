class AddParentChatIdToChats < ActiveRecord::Migration[8.1]
  def change
    add_reference :chats, :parent_chat, null: true, foreign_key: { to_table: :chats }
  end
end
