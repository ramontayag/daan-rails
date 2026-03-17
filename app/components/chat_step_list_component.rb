class ChatStepListComponent < ViewComponent::Base
  def initialize(chat:)
    @chat = chat
  end

  private

  attr_reader :chat

  def steps
    @steps ||= chat.chat_steps.to_a
  end

  def render?
    steps.any?
  end

  def status_icon(status)
    case status
    when "completed"   then "✓"
    when "in_progress" then "●"
    else                    " "
    end
  end

  def status_class(status)
    case status
    when "completed"   then "text-green-600 line-through"
    when "in_progress" then "text-blue-600 font-medium"
    else                    "text-gray-500"
    end
  end
end
