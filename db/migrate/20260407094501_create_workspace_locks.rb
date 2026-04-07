class CreateWorkspaceLocks < ActiveRecord::Migration[8.1]
  def change
    create_table :workspace_locks do |t|
      t.string :agent_name, null: false
      t.references :holder_chat, null: true, foreign_key: { to_table: :chats }
      t.references :previous_holder_chat, null: true, foreign_key: { to_table: :chats }
      t.timestamps
    end

    add_index :workspace_locks, :agent_name, unique: true
  end
end
