# test/models/chat_test.rb
require "test_helper"

class ChatTest < ActiveSupport::TestCase
  setup do
    @agent = Daan::Agent.new(name: "chief_of_staff", display_name: "CoS",
                             model_name: "claude-sonnet-4-20250514",
                             system_prompt: "You are CoS.", max_steps: 10)
    Daan::AgentRegistry.register(@agent)
  end

  test "agent returns the registered Daan::Agent" do
    chat = Chat.new(agent_name: "chief_of_staff")
    assert_equal @agent, chat.agent
  end

  test "defaults to pending state" do
    assert Chat.new.pending?
  end

  test "start! transitions pending to in_progress" do
    chat = chats(:hello_cos)
    chat.start!
    assert chat.in_progress?
  end

  test "finish! transitions in_progress to completed" do
    chat = chats(:hello_cos)
    chat.start!
    chat.finish!
    assert chat.completed?
  end

  test "invalid transition raises AASM::InvalidTransition" do
    chat = chats(:hello_cos)
    assert_raises(AASM::InvalidTransition) { chat.finish! }
  end

  test "step_count returns 0 with no messages" do
    chat = Chat.new(agent_name: "chief_of_staff")
    assert_equal 0, chat.step_count
  end


  test "raises AgentNotFoundError for unknown agent_name" do
    chat = Chat.new(agent_name: "ghost")
    assert_raises(Daan::AgentNotFoundError) { chat.agent }
  end

  test "parent_chat is optional" do
    chat = Chat.create!(agent_name: "chief_of_staff")
    assert_nil chat.parent_chat
  end

  test "sub_chats association returns child chats" do
    parent = Chat.create!(agent_name: "chief_of_staff")
    child  = Chat.create!(agent_name: "chief_of_staff", parent_chat: parent)
    assert_includes parent.sub_chats, child
  end

  test "parent_chat association returns parent" do
    parent = Chat.create!(agent_name: "chief_of_staff")
    child  = Chat.create!(agent_name: "chief_of_staff", parent_chat: parent)
    assert_equal parent, child.parent_chat
  end

  test "conversation_partner_names_for returns agents who delegated to this agent" do
    parent = Chat.create!(agent_name: "chief_of_staff")
    Chat.create!(agent_name: "engineering_manager", parent_chat: parent)
    assert_includes Chat.conversation_partner_names_for("engineering_manager"), "chief_of_staff"
  end

  test "conversation_partner_names_for returns agents this agent delegated to" do
    parent = Chat.create!(agent_name: "engineering_manager")
    Chat.create!(agent_name: "developer", parent_chat: parent)
    assert_includes Chat.conversation_partner_names_for("engineering_manager"), "developer"
  end

  test "conversation_partner_names_for returns empty array when no chats" do
    assert_equal [], Chat.conversation_partner_names_for("developer")
  end

  # Token calculation tests
  test "total_input_tokens returns sum of all message input tokens" do
    chat = chats(:hello_cos)
    chat.messages.create!(role: "user", content: "Hello", input_tokens: 100)
    chat.messages.create!(role: "assistant", content: "Hi", input_tokens: 50)
    assert_equal 150, chat.total_input_tokens
  end

  test "total_output_tokens returns sum of all message output tokens" do
    chat = chats(:hello_cos)
    chat.messages.create!(role: "user", content: "Hello", output_tokens: 0)
    chat.messages.create!(role: "assistant", content: "Hi", output_tokens: 25)
    assert_equal 25, chat.total_output_tokens
  end

  test "total_cached_tokens returns sum of all message cached tokens" do
    chat = chats(:hello_cos)
    chat.messages.create!(role: "user", content: "Hello", cached_tokens: 30)
    chat.messages.create!(role: "assistant", content: "Hi", cached_tokens: 20)
    assert_equal 50, chat.total_cached_tokens
  end

  test "total_thinking_tokens returns sum of all message thinking tokens" do
    chat = chats(:hello_cos)
    chat.messages.create!(role: "assistant", content: "Hi", thinking_tokens: 75)
    chat.messages.create!(role: "assistant", content: "Bye", thinking_tokens: 25)
    assert_equal 100, chat.total_thinking_tokens
  end

  test "total_tokens returns sum of input, output, and thinking tokens" do
    chat = chats(:hello_cos)
    chat.messages.create!(role: "user", content: "Hello", input_tokens: 100, output_tokens: 0, thinking_tokens: 0)
    chat.messages.create!(role: "assistant", content: "Hi", input_tokens: 0, output_tokens: 25, thinking_tokens: 50)
    assert_equal 175, chat.total_tokens
  end

  test "token totals handle nil values" do
    chat = chats(:hello_cos)
    chat.messages.create!(role: "user", content: "Hello") # All token fields will be nil
    assert_equal 0, chat.total_input_tokens
    assert_equal 0, chat.total_output_tokens
    assert_equal 0, chat.total_cached_tokens
    assert_equal 0, chat.total_thinking_tokens
    assert_equal 0, chat.total_tokens
  end

  test "estimated_cost_usd returns 0 when no model" do
    chat = Chat.create!(agent_name: "chief_of_staff")
    chat.update!(model: nil)
    assert_equal 0.0, chat.estimated_cost_usd
  end

  test "estimated_cost_usd returns 0 when model has no pricing" do
    model = Model.create!(
      name: "Test Model",
      model_id: "test-model",
      provider: "test",
      pricing: {}
    )
    chat = chats(:hello_cos)
    chat.update!(model: model)
    assert_equal 0.0, chat.estimated_cost_usd
  end

  test "estimated_cost_usd calculates cost correctly with pricing" do
    model = Model.create!(
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

    chat = chats(:hello_cos)
    chat.update!(model: model)
    chat.messages.create!(
      role: "user",
      content: "Hello",
      input_tokens: 1000,
      output_tokens: 500,
      cached_tokens: 200,
      thinking_tokens: 300
    )

    # Expected: (1000 + 300) * $1/M + 500 * $2/M + 200 * $0.1/M
    #         = 1300 * 0.001 + 500 * 0.002 + 200 * 0.0001
    #         = 0.0013 + 0.001 + 0.00002 = 0.00232
    expected_cost = 0.00232
    assert_in_delta expected_cost, chat.estimated_cost_usd, 0.000001
  end

  test "total_cost_usd returns own cost when no sub_chats" do
    model = Model.create!(
      name: "Test Model", model_id: "test-model", provider: "test",
      pricing: { "data" => { "text_tokens" => { "standard" => { "values" => {
        "input_per_million" => 1.0, "output_per_million" => 2.0, "cached_input_per_million" => 0.1
      } } } } }
    )
    chat = chats(:hello_cos)
    chat.update!(model: model)
    chat.messages.create!(role: "user", content: "Hello", input_tokens: 1_000_000)

    assert_in_delta 1.0, chat.total_cost_usd, 0.000001
  end

  test "total_cost_usd includes direct sub_chat costs" do
    model = Model.create!(
      name: "Test Model", model_id: "test-model", provider: "test",
      pricing: { "data" => { "text_tokens" => { "standard" => { "values" => {
        "input_per_million" => 1.0, "output_per_million" => 0.0, "cached_input_per_million" => 0.0
      } } } } }
    )
    parent = Chat.create!(agent_name: "chief_of_staff", model: model)
    child  = Chat.create!(agent_name: "chief_of_staff", model: model, parent_chat: parent)

    parent.messages.create!(role: "user", content: "a", input_tokens: 1_000_000)
    child.messages.create!(role: "user", content: "b", input_tokens: 2_000_000)

    assert_in_delta 3.0, parent.total_cost_usd, 0.000001
  end

  test "total_cost_usd is recursive through grandchildren" do
    model = Model.create!(
      name: "Test Model", model_id: "test-model", provider: "test",
      pricing: { "data" => { "text_tokens" => { "standard" => { "values" => {
        "input_per_million" => 1.0, "output_per_million" => 0.0, "cached_input_per_million" => 0.0
      } } } } }
    )
    grandparent = Chat.create!(agent_name: "chief_of_staff", model: model)
    parent      = Chat.create!(agent_name: "chief_of_staff", model: model, parent_chat: grandparent)
    child       = Chat.create!(agent_name: "chief_of_staff", model: model, parent_chat: parent)

    grandparent.messages.create!(role: "user", content: "a", input_tokens: 1_000_000)
    parent.messages.create!(role: "user", content: "b", input_tokens: 1_000_000)
    child.messages.create!(role: "user", content: "c", input_tokens: 1_000_000)

    assert_in_delta 3.0, grandparent.total_cost_usd, 0.000001
  end

  test "total_tokens_including_sub_chats includes own and all descendant tokens" do
    parent = Chat.create!(agent_name: "chief_of_staff")
    child  = Chat.create!(agent_name: "chief_of_staff", parent_chat: parent)

    parent.messages.create!(role: "user", content: "a", input_tokens: 100, output_tokens: 0, thinking_tokens: 0)
    child.messages.create!(role: "user", content: "b", input_tokens: 200, output_tokens: 0, thinking_tokens: 0)

    assert_equal 300, parent.total_tokens_including_sub_chats
  end

  test "formatted_cost displays correctly for different amounts" do
    model = Model.create!(
      name: "Test Model",
      model_id: "test-model",
      provider: "test",
      pricing: {
        "data" => {
          "text_tokens" => {
            "standard" => {
              "values" => {
                "input_per_million" => 10.0,
                "output_per_million" => 20.0,
                "cached_input_per_million" => 1.0
              }
            }
          }
        }
      }
    )

    chat = chats(:hello_cos)
    chat.update!(model: model)

    # Test large amount (>= $1.00)
    chat.messages.create!(role: "user", content: "Hello", input_tokens: 150_000, output_tokens: 100_000)
    assert_equal "$3.50", chat.formatted_cost

    # Test medium amount (>= $0.01)
    chat.messages.destroy_all
    chat.messages.create!(role: "user", content: "Hello", input_tokens: 1_500, output_tokens: 1_000)
    assert_equal "$0.035", chat.formatted_cost

    # Test small amount (< $0.01)
    chat.messages.destroy_all
    chat.messages.create!(role: "user", content: "Hello", input_tokens: 150, output_tokens: 100)
    assert_equal "$0.0035", chat.formatted_cost
  end
end
