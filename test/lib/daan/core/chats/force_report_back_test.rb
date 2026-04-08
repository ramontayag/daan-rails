# test/lib/daan/chats/force_report_back_test.rb
require "test_helper"
require "ostruct"

class Daan::Core::Chats::ForceReportBackTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @agent = build_agent
    Daan::Core::AgentRegistry.register(@agent)
    @chat = Chat.create!(agent_name: @agent.name)
    @chat.messages.create!(role: "user", content: "Do the thing")
    @chat.start!
    3.times { |i| @chat.messages.create!(role: "assistant", content: "step #{i}") }
  end

  test "adds a user message asking the agent to summarize" do
    stub_toolless_step("Here is my summary.") do
      Daan::Core::Chats::ForceReportBack.call(@chat)
    end

    summary_prompt = @chat.messages.where(role: "user").order(:id).last
    assert_equal false, summary_prompt.visible
    assert_includes summary_prompt.content, "summarize"
  end

  test "makes a tool-less LLM call and saves the response" do
    stub_toolless_step("Here is my summary.") do
      Daan::Core::Chats::ForceReportBack.call(@chat)
    end

    last_assistant = @chat.messages.where(role: "assistant").order(:id).last
    assert_equal "Here is my summary.", last_assistant.content
  end

  test "strips tools before calling step" do
    tools_passed = :not_called
    @chat.define_singleton_method(:with_tools) do |*args|
      tools_passed = args
      self
    end
    @chat.define_singleton_method(:step) do
      msg = messages.create!(role: "assistant", content: "Summary")
      OpenStruct.new(tool_call?: false, role: "assistant", tool_calls: nil, content: "Summary")
    end

    Daan::Core::Chats::ForceReportBack.call(@chat)
    assert_equal [], tools_passed
  end

  test "broadcasts the summary message" do
    stub_toolless_step("Here is my summary.") do
      Daan::Core::Chats::ForceReportBack.call(@chat)
    end

    last_assistant = @chat.messages.where(role: "assistant").order(:id).last
    assert last_assistant, "Expected a summary assistant message"
  end

  test "lets errors propagate" do
    @chat.define_singleton_method(:with_tools) { |*_| self }
    @chat.define_singleton_method(:step) { raise "LLM exploded" }

    assert_raises(RuntimeError, "LLM exploded") do
      Daan::Core::Chats::ForceReportBack.call(@chat)
    end
  end

  private

  def stub_toolless_step(content)
    @chat.define_singleton_method(:with_tools) do |*_args|
      self
    end
    @chat.define_singleton_method(:step) do
      messages.create!(role: "assistant", content: content)
      OpenStruct.new(tool_call?: false, role: "assistant", tool_calls: nil, content: content)
    end

    yield
  ensure
    @chat.singleton_class.remove_method(:with_tools) if @chat.singleton_class.method_defined?(:with_tools)
    @chat.singleton_class.remove_method(:step) if @chat.singleton_class.method_defined?(:step)
  end
end
