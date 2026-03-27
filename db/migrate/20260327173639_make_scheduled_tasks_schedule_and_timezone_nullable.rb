class MakeScheduledTasksScheduleAndTimezoneNullable < ActiveRecord::Migration[8.1]
  def change
    change_column_null :scheduled_tasks, :schedule, true
    change_column_null :scheduled_tasks, :timezone, true
  end
end
