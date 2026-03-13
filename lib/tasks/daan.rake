namespace :daan do
  desc "Re-enqueue LlmJob for stuck in_progress chats. Pass CHAT_ID=<id> to target a single chat."
  task recover_stuck_chats: :environment do
    chats = if ENV["CHAT_ID"].present?
      Chat.where(id: ENV["CHAT_ID"], task_status: "in_progress")
    else
      Chat.where(task_status: "in_progress")
    end

    if chats.none?
      puts "No stuck chats found."
    else
      chats.each do |chat|
        LlmJob.perform_later(chat)
        puts "Enqueued LlmJob for Chat ##{chat.id} (#{chat.agent_name})"
      end
    end
  end
end
