class CreateScheduledTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :scheduled_tasks do |t|
      t.string   :agent_name,       null: false
      t.text     :message,          null: false
      t.string   :schedule,         null: false
      t.string   :timezone,         null: false, default: "UTC"
      t.datetime :last_enqueued_at
      t.boolean  :enabled,          null: false, default: true

      t.timestamps
    end

    add_index :scheduled_tasks, :agent_name
    add_index :scheduled_tasks, :enabled
  end
end
