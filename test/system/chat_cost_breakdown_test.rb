require "application_system_test_case"

class ChatCostBreakdownTest < ApplicationSystemTestCase
  setup do
    Chat.destroy_all
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))

    @model = Model.find_or_create_by!(model_id: "test-cost-model") do |m|
      m.name = "Test Model"
      m.provider = "test"
      m.pricing = { "data" => { "text_tokens" => { "standard" => { "values" => {
        "input_per_million" => 1.0, "output_per_million" => 0.0, "cached_input_per_million" => 0.0
      } } } } }
    end

    @parent = Chat.create!(agent_name: "chief_of_staff", model: @model)
    @child  = Chat.create!(agent_name: "developer", model: @model, parent_chat: @parent)

    @parent.messages.create!(role: "user", content: "hello", input_tokens: 1_000_000, output_tokens: 0, thinking_tokens: 0)
    @child.messages.create!(role: "user", content: "hi", input_tokens: 2_000_000, output_tokens: 0, thinking_tokens: 0)

    ActiveJob::Base.queue_adapter = :test
  end

  test "shows grand total tokens and cost in header" do
    visit chat_thread_path(@parent)

    within "[data-controller='cost-breakdown']" do
      assert_text "3,000,000"
      assert_text "$3.00"
    end
  end

  test "clicking cost button opens breakdown panel with per-chat rows" do
    visit chat_thread_path(@parent)

    find("[data-action='cost-breakdown#toggle']").click

    within "[data-cost-breakdown-target='panel']" do
      assert_text "Chief of Staff"
      assert_text "Developer"
    end
  end

  test "leaf chat shows plain cost with no breakdown button" do
    solo = Chat.create!(agent_name: "chief_of_staff", model: @model)
    solo.messages.create!(role: "user", content: "hello", input_tokens: 500_000, output_tokens: 0, thinking_tokens: 0)

    visit chat_thread_path(solo)

    assert_text "500,000"
    assert_no_selector "[data-controller='cost-breakdown']"
  end
end
