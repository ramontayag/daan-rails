class AddOneShotFieldsToScheduledTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :scheduled_tasks, :task_type, :integer, null: false, default: 0
    add_column :scheduled_tasks, :run_at, :datetime, null: true
    add_column :scheduled_tasks, :source_chat_id, :bigint, null: true

    add_foreign_key :scheduled_tasks, :chats, column: :source_chat_id
    add_index :scheduled_tasks, :source_chat_id
    add_index :scheduled_tasks, [ :task_type, :enabled, :run_at ],
              name: "index_scheduled_tasks_on_type_enabled_run_at"
  end
end
