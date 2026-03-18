class CreateChatSteps < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_steps do |t|
      t.references :chat, null: false, foreign_key: true
      t.string :title, null: false
      t.string :status, null: false, default: "pending"
      t.integer :position, null: false

      t.timestamps
    end

    add_index :chat_steps, [ :chat_id, :position ], unique: true
  end
end
