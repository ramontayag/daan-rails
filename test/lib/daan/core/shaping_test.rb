require "test_helper"
require "ostruct"

class Daan::Core::ShapingTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup do
    agent = Daan::Core::Agent.new(
      name: "ryan_singer", display_name: "Ryan Singer",
      model_name: "claude-sonnet-4-6", system_prompt: "You shape.",
      max_steps: 20
    )
    Daan::Core::AgentRegistry.register(agent)
    @chat = Chat.create!(agent_name: "ryan_singer")
    @hook = Daan::Core::Shaping.new
  end

  def call_hook(last_tool_calls: [])
    @hook.before_llm_call(chat: @chat, last_tool_calls: last_tool_calls)
  end

  test "does nothing when last_tool_calls is empty" do
    assert_no_difference -> { @chat.messages.count } do
      call_hook
    end
  end

  test "does nothing when last_tool_calls has no update_document call" do
    tc = build_tool_call(Daan::Core::Read.tool_name)
    assert_no_difference -> { @chat.messages.count } do
      call_hook(last_tool_calls: [ tc ])
    end
  end

  test "injects a visible:false ripple-check message when update_document was called" do
    tc = build_tool_call(Daan::Core::UpdateDocument.tool_name)
    assert_difference -> { @chat.messages.count }, 1 do
      call_hook(last_tool_calls: [ tc ])
    end

    msg = @chat.messages.order(:id).last
    assert_equal "user", msg.role
    assert_equal false, msg.visible
    assert_includes msg.content, "Ripple check"
  end

  test "injects exactly one message even when multiple update_document calls in one turn" do
    tcs = [
      build_tool_call(Daan::Core::UpdateDocument.tool_name),
      build_tool_call(Daan::Core::UpdateDocument.tool_name)
    ]
    assert_difference -> { @chat.messages.count }, 1 do
      call_hook(last_tool_calls: tcs)
    end
  end

  test "does not enqueue LlmJob when injecting ripple check" do
    tc = build_tool_call(Daan::Core::UpdateDocument.tool_name)
    assert_no_enqueued_jobs only: LlmJob do
      call_hook(last_tool_calls: [ tc ])
    end
  end

  private

  # Build a minimal ToolCall-like double for the hook interface.
  # Daan::Core::Shaping only checks tc.name, so an OpenStruct suffices.
  def build_tool_call(name)
    OpenStruct.new(name: name)
  end
end
