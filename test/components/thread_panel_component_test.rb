require "test_helper"

class ThreadPanelComponentTest < ViewComponent::TestCase
  setup do
    @agent = Daan::Agent.new(name: "developer", display_name: "Developer",
                             model_name: "claude-sonnet-4-20250514",
                             system_prompt: "You are a developer.", max_steps: 10)
    Daan::AgentRegistry.register(@agent)

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

    @chat = Chat.create!(agent_name: "developer", model: @model)
  end

  test "displays token count when chat has messages with tokens" do
    @chat.messages.create!(
      role: "user",
      content: "Hello",
      input_tokens: 1000,
      output_tokens: 500,
      thinking_tokens: 200
    )

    render_inline(ThreadPanelComponent.new(chat: @chat, perspective_name: "me"))

    assert_text "1,700 tokens"
  end

  test "displays cost when chat has non-zero cost" do
    @chat.messages.create!(
      role: "user",
      content: "Hello",
      input_tokens: 50000,  # Will result in $0.05+ cost
      output_tokens: 25000
    )

    render_inline(ThreadPanelComponent.new(chat: @chat, perspective_name: "me"))

    assert_text "$0.100" # Should display cost
  end

  test "does not display cost when cost is zero" do
    # Chat with no messages or zero tokens
    render_inline(ThreadPanelComponent.new(chat: @chat, perspective_name: "me"))

    refute_text "$" # Should not show any cost
    assert_text "0 tokens"
  end

  test "displays hide tools toggle" do
    render_inline(ThreadPanelComponent.new(chat: @chat, perspective_name: "me", hide_tools: false))

    assert_selector "a", text: "Hide tools"
  end

  test "displays show tools toggle when tools hidden" do
    render_inline(ThreadPanelComponent.new(chat: @chat, perspective_name: "me", hide_tools: true))

    assert_selector "a", text: "Show tools"
  end

  test "displays back link on mobile" do
    render_inline(ThreadPanelComponent.new(chat: @chat, perspective_name: "me"))

    assert_selector ".md\\:hidden a", text: "← Back"
  end

  test "shows documents icon when chat has documents" do
    Document.create!(title: "My Plan", body: "# Plan", chat: @chat)
    render_inline(ThreadPanelComponent.new(chat: @chat, perspective_name: "me"))
    assert_selector "[title='Show documents']"
  end

  test "does not show documents icon when no documents" do
    render_inline(ThreadPanelComponent.new(chat: @chat, perspective_name: "me"))
    refute_selector "[title='Show documents']"
  end

  test "shows documents panel when show_docs is true and documents exist" do
    Document.create!(title: "My Plan", body: "# Plan", chat: @chat)
    render_inline(ThreadPanelComponent.new(chat: @chat, perspective_name: "me", show_docs: true))
    assert_text "My Plan"
  end

  test "formats large token numbers with commas" do
    @chat.messages.create!(
      role: "user",
      content: "Hello",
      input_tokens: 1234567
    )

    render_inline(ThreadPanelComponent.new(chat: @chat, perspective_name: "me"))

    assert_text "1,234,567 tokens"
  end
end
