require "test_helper"

class ChatHeaderStatsComponentTest < ViewComponent::TestCase
  setup do
    @model = Model.create!(
      name: "Test Model",
      model_id: "test-model",
      provider: "test",
      pricing: {
        "data" => {
          "text_tokens" => {
            "standard" => {
              "values" => {
                "input_per_million" => 1.0,
                "output_per_million" => 2.0,
                "cached_input_per_million" => 0.1
              }
            }
          }
        }
      }
    )

    Daan::AgentRegistry.register(Daan::Agent.new(
      name: "test_agent",
      display_name: "Test Agent",
      model_name: "test-model",
      system_prompt: "Test",
      max_turns: 10
    ))

    @chat = Chat.create!(agent_name: "test_agent", model: @model)
  end

  test "displays token count" do
    @chat.messages.create!(
      role: "user",
      content: "Hello",
      input_tokens: 1000,
      output_tokens: 500
    )

    render_inline(ChatHeaderStatsComponent.new(chat: @chat))

    assert_text "1,500 tokens"
  end

  test "displays cost when non-zero" do
    @chat.messages.create!(
      role: "user",
      content: "Hello",
      input_tokens: 50000,
      output_tokens: 25000
    )

    render_inline(ChatHeaderStatsComponent.new(chat: @chat))

    assert_text "$0.100"
    assert_text "75,000 tokens"
  end

  test "does not display cost when zero" do
    render_inline(ChatHeaderStatsComponent.new(chat: @chat))

    refute_text "$"
    assert_text "0 tokens"
  end

  test "formats large token numbers with commas" do
    @chat.messages.create!(
      role: "user",
      content: "Hello",
      input_tokens: 1234567
    )

    render_inline(ChatHeaderStatsComponent.new(chat: @chat))

    assert_text "1,234,567 tokens"
  end

  test "uses smart cost formatting" do
    # Test large cost (>= $1.00) - 2 decimals
    # 1M input @ $1.0 per M + 1M output @ $2.0 per M = $3.00
    @chat.messages.create!(
      role: "user",
      content: "Test",
      input_tokens: 1000000,
      output_tokens: 1000000
    )

    render_inline(ChatHeaderStatsComponent.new(chat: @chat))

    assert_text "2,000,000 tokens"
    assert_text "$3.00"
  end
end
