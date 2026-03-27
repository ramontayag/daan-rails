class ScheduledTask < ApplicationRecord
  validates :agent_name, presence: true
  validates :message,    presence: true
  validates :schedule,   presence: true
  validates :timezone,   presence: true
  validate  :schedule_must_be_parseable

  scope :enabled, -> { where(enabled: true) }

  # Returns true if the most recent expected tick of the cron schedule is
  # after last_enqueued_at (or last_enqueued_at is nil), meaning the task
  # is due to fire.
  #
  # NOTE: `timezone` is stored and displayed but not yet applied to the schedule
  # computation. Fugit parses the schedule as UTC. Timezone-aware firing is
  # deferred to a future slice.
  def due?
    cron = Fugit.parse(schedule)
    raise ArgumentError, "Cannot parse schedule: #{schedule.inspect}" unless cron

    now = Time.current
    # previous_time returns the most recent tick at or before `now`
    last_tick = cron.previous_time(now)
    return true if last_enqueued_at.nil?

    last_tick.to_t > last_enqueued_at
  end

  private

  def schedule_must_be_parseable
    return if schedule.blank?
    errors.add(:schedule, "is not a valid schedule") unless Fugit.parse(schedule)
  end
end
