class LlmJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: ->(chat) { "chat_#{chat.id}" }

  def perform(chat)
    Rails.logger.info("[LlmJob] start chat_id=#{chat.id} agent=#{chat.agent_name} status=#{chat.task_status}")
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    Daan::ConversationRunner.call(chat)

    elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at).round(1)
    Rails.logger.info("[LlmJob] done chat_id=#{chat.id} agent=#{chat.agent_name} elapsed=#{elapsed}s")
  rescue => e
    elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at).round(1) if started_at
    Rails.logger.error("[LlmJob] failed chat_id=#{chat.id} agent=#{chat.agent_name} elapsed=#{elapsed}s error=#{e.class}: #{e.message}")
    chat.reload
    chat.fail! if chat.may_fail?
    Daan::Chats::ReleaseWorkspace.call(chat)
    chat.broadcast_agent_status
    raise
  end
end
