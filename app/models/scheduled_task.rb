class ScheduledTask < ApplicationRecord
  enum :task_type, { recurring: 0, one_shot: 1 }, default: :recurring

  belongs_to :source_chat, class_name: "Chat", optional: true

  validates :agent_name, presence: true
  validates :message,    presence: true
  validates :schedule,   presence: true, if: :recurring?
  validates :timezone,   presence: true, if: :recurring?
  validates :run_at,     presence: true, if: :one_shot?
  validate  :schedule_must_be_parseable

  scope :enabled,      -> { where(enabled: true) }
  scope :one_shot_due, -> {
    where(task_type: task_types[:one_shot], enabled: true)
      .where(arel_table[:run_at].lteq(Time.current))
  }

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
