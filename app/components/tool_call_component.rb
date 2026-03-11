# app/components/tool_call_component.rb
class ToolCallComponent < ViewComponent::Base
  def initialize(tool_call:, result: nil, agent_display_name: nil)
    @tool_call          = tool_call
    @result             = result
    @agent_display_name = agent_display_name
  end

  private

  attr_reader :tool_call, :agent_display_name

  def tool_name = tool_call.name
  def arguments = tool_call.arguments
  def result = @result || Message.find_by(tool_call_id: tool_call.id)&.content

  def initials
    return "?" unless agent_display_name
    agent_display_name.split.first(2).map { |w| w[0] }.join.upcase
  end
end
