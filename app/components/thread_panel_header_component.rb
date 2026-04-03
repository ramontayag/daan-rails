class ThreadPanelHeaderComponent < ViewComponent::Base
  def initialize(chat:, show_tasks:, hide_tools:)
    @chat       = chat
    @show_tasks = show_tasks
    @hide_tools = hide_tools
  end

  private

  attr_reader :chat, :show_tasks, :hide_tools

  def show_tasks_toggle?
    chat.chat_steps.any?
  end

  def tasks_toggle_path
    helpers.chat_thread_path(chat, show_tasks: show_tasks ? "0" : "1")
  end

  def tasks_toggle_title
    show_tasks ? "Hide steps" : "Show steps"
  end

  def tools_toggle_path
    helpers.chat_thread_path(chat, show_tools: hide_tools ? "1" : "0")
  end

  def tools_toggle_title
    hide_tools ? "Show tools" : "Hide tools"
  end

  def tools_link_classes
    color = hide_tools ? "text-gray-300 hover:text-gray-500" : "text-gray-800 hover:text-black"
    "inline-flex #{color}"
  end

  def agent_path
    helpers.chat_agent_path(chat.agent)
  end
end
