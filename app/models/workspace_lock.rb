class WorkspaceLock < ApplicationRecord
  belongs_to :holder_chat, class_name: "Chat", optional: true
  belongs_to :previous_holder_chat, class_name: "Chat", optional: true

  AcquireResult = Struct.new(:acquired?, :previous_holder_chat_id, keyword_init: true)

  def self.acquire(chat:, agent_name:)
    lock = find_or_create_by!(agent_name: agent_name)

    lock.with_lock do
      if lock.holder_chat_id.nil?
        previous = lock.previous_holder_chat_id
        lock.update!(holder_chat: chat)
        changed_hands = previous && previous != chat.id
        AcquireResult.new(acquired?: true, previous_holder_chat_id: changed_hands ? previous : nil)
      elsif lock.holder_chat_id == chat.id
        lock.touch
        AcquireResult.new(acquired?: true, previous_holder_chat_id: nil)
      elsif lock.stale?
        stale_holder_id = lock.holder_chat_id
        lock.update!(holder_chat: chat, previous_holder_chat_id: stale_holder_id)
        AcquireResult.new(acquired?: true, previous_holder_chat_id: stale_holder_id)
      else
        AcquireResult.new(acquired?: false, previous_holder_chat_id: nil)
      end
    end
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def self.release(chat:, agent_name:)
    lock = find_by(agent_name: agent_name)
    return unless lock

    lock.with_lock do
      return unless lock.holder_chat_id == chat.id

      lock.update!(holder_chat: nil, previous_holder_chat: chat)
    end
  end

  GRACE_PERIOD = 30.seconds

  def stale?
    tag = "[WorkspaceLock] holder_chat_id=#{holder_chat_id}"

    unless holder_chat&.in_progress?
      Rails.logger.info("#{tag} stale: chat not in_progress (status=#{holder_chat&.task_status})")
      return true
    end

    if updated_at > GRACE_PERIOD.ago
      Rails.logger.info("#{tag} not stale: within grace period (updated_at=#{updated_at})")
      return false
    end

    gid = holder_chat.to_global_id.to_s
    job_table = SolidQueue::Job.arel_table
    has_job = SolidQueue::Job
      .where(class_name: "LlmJob", finished_at: nil)
      .where(job_table[:arguments].matches("%\"_aj_globalid\":\"#{gid}\"%"))
      .exists?

    Rails.logger.info("#{tag} grace expired (updated_at=#{updated_at}), has_job=#{has_job}")
    !has_job
  end
end
