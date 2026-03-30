class ScheduledTaskRunnerJob < ApplicationJob
  queue_as :default

  def perform(task)
    agent = Daan::AgentRegistry.find(task.agent_name)

    chat = if task.source_chat.present?
      task.source_chat.tap { |c| c.continue! if c.completed? || c.failed? || c.blocked? }
    else
      Chat.create!(agent_name: agent.name, model: agent.model_name).tap do |c|
        c.messages.create!(
          role: "system",
          content: "This conversation was started automatically by a scheduled task.",
          visible: false
        )
      end
    end

    chat.messages.create!(role: "user", content: task.message, visible: true)
    LlmJob.perform_later(chat)
    task.update!(enabled: false) if task.one_shot?
  end
end
