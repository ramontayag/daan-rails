class ScheduledTaskPollerJob < ApplicationJob
  queue_as :background

  def perform
    ScheduledTask.enabled.each do |task|
      next unless task.due?

      ScheduledTaskRunnerJob.perform_later(task)
      task.update_column(:last_enqueued_at, Time.current)
    rescue => e
      Rails.logger.error(
        "[ScheduledTaskPollerJob] task_id=#{task.id} error=#{e.class}: #{e.message}"
      )
      # Silent failure — log and continue to next task
    end
  end
end
