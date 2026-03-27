class ScheduledTaskRunnerJob < ApplicationJob
  queue_as :default

  def perform(task)
    agent = Daan::AgentRegistry.find(task.agent_name)
    chat  = Chat.create!(agent_name: agent.name, model: agent.model_name)

    # Invisible system message so ConversationRunner knows this was auto-started.
    chat.messages.create!(
      role: "system",
      content: "This conversation was started automatically by a scheduled task.",
      visible: false
    )

    # Visible user message — the actual task payload.
    chat.messages.create!(role: "user", content: task.message, visible: true)

    LlmJob.perform_later(chat)
    task.update!(enabled: false) if task.one_shot?
  end
end
