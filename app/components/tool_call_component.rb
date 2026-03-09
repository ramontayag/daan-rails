# app/components/tool_call_component.rb
class ToolCallComponent < ViewComponent::Base
  def initialize(tool_call:, result: nil)
    @tool_call = tool_call
    @result = result
  end

  private

  attr_reader :tool_call

  def tool_name = tool_call.name
  def arguments = tool_call.arguments
  def result = @result || Message.find_by(tool_call_id: tool_call.id)&.content
end
