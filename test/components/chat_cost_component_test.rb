require "test_helper"

class ChatCostComponentTest < ViewComponent::TestCase
  setup do
    Daan::Core::AgentRegistry.register(Daan::Core::Agent.new(
      name: "chief_of_staff", display_name: "Chief of Staff",
      model_name: "claude-sonnet-4-20250514", system_prompt: "p", max_steps: 10
    ))
    Daan::Core::AgentRegistry.register(Daan::Core::Agent.new(
      name: "developer", display_name: "Developer",
      model_name: "claude-sonnet-4-20250514", system_prompt: "p", max_steps: 10
    ))

    @model = Model.create!(
      name: "Test Model", model_id: "test-model", provider: "test",
      pricing: { "text_tokens" => { "standard" => {
        "input_per_million" => 1.0, "output_per_million" => 0.0, "cached_input_per_million" => 0.0
      } } }
    )
  end

  test "shows total tokens from this chat only when no sub_chats" do
    chat = Chat.create!(agent_name: "chief_of_staff", model: @model)
    chat.messages.create!(role: "user", content: "hi", input_tokens: 500, output_tokens: 0, thinking_tokens: 0)

    render_inline(ChatCostComponent.new(chat: chat))

    assert_text "500 tokens"
  end

  test "shows total tokens including sub_chats" do
    parent = Chat.create!(agent_name: "chief_of_staff", model: @model)
    child  = Chat.create!(agent_name: "developer", model: @model, parent_chat: parent)
    parent.messages.create!(role: "user", content: "hi", input_tokens: 300, output_tokens: 0, thinking_tokens: 0)
    child.messages.create!(role: "user", content: "hi", input_tokens: 200, output_tokens: 0, thinking_tokens: 0)

    render_inline(ChatCostComponent.new(chat: parent))

    assert_includes rendered_content, "500"
    assert_includes rendered_content, "tokens"
  end

  test "shows total cost including sub_chats" do
    parent = Chat.create!(agent_name: "chief_of_staff", model: @model)
    child  = Chat.create!(agent_name: "developer", model: @model, parent_chat: parent)
    parent.messages.create!(role: "user", content: "hi", input_tokens: 1_000_000, output_tokens: 0, thinking_tokens: 0)
    child.messages.create!(role: "user", content: "hi", input_tokens: 2_000_000, output_tokens: 0, thinking_tokens: 0)

    render_inline(ChatCostComponent.new(chat: parent))

    assert_text "$3.00"
  end

  test "shows no breakdown toggle when no sub_chats" do
    chat = Chat.create!(agent_name: "chief_of_staff", model: @model)

    render_inline(ChatCostComponent.new(chat: chat))

    assert_no_selector "[data-controller='popover']"
  end

  test "shows breakdown toggle when sub_chats exist" do
    parent = Chat.create!(agent_name: "chief_of_staff", model: @model)
    Chat.create!(agent_name: "developer", model: @model, parent_chat: parent)

    render_inline(ChatCostComponent.new(chat: parent))

    assert_selector "[data-controller='popover']"
  end

  test "breakdown lists this chat and each sub_chat with costs" do
    parent = Chat.create!(agent_name: "chief_of_staff", model: @model)
    child  = Chat.create!(agent_name: "developer", model: @model, parent_chat: parent)
    parent.messages.create!(role: "user", content: "hi", input_tokens: 1_000_000, output_tokens: 0, thinking_tokens: 0)
    child.messages.create!(role: "user", content: "hi", input_tokens: 2_000_000, output_tokens: 0, thinking_tokens: 0)

    render_inline(ChatCostComponent.new(chat: parent))

    assert_text "Chief of Staff"
    assert_text "Developer"
  end
end
