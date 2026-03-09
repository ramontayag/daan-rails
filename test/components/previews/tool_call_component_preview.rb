# test/components/previews/tool_call_component_preview.rb
class ToolCallComponentPreview < ViewComponent::Preview
  def with_result
    chat = Chat.first_or_create!(agent_name: "chief_of_staff")
    msg = chat.messages.first_or_create!(role: "assistant", content: nil)
    tc = ToolCall.find_or_create_by!(tool_call_id: "prev_001") do |t|
      t.message = msg
      t.name = "read"
      t.arguments = { "path" => "hello.txt" }
    end
    render ToolCallComponent.new(tool_call: tc, result: "Hello, world!")
  end

  def running
    chat = Chat.first_or_create!(agent_name: "chief_of_staff")
    msg = chat.messages.first_or_create!(role: "assistant", content: nil)
    tc = ToolCall.find_or_create_by!(tool_call_id: "prev_002") do |t|
      t.message = msg
      t.name = "write"
      t.arguments = { "path" => "output.txt", "content" => "hello" }
    end
    render ToolCallComponent.new(tool_call: tc)
  end
end
