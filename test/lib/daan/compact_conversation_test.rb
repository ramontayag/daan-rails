require "test_helper"
require "ostruct"

class Daan::CompactConversationTest < ActiveSupport::TestCase
  include ActionCable::TestHelper
  setup do
    @chat = chats(:hello_cos)
    @agent = Daan::Agent.new(
      name: "test", display_name: "Test",
      model_name: "claude-haiku-4-5-20251001",
      system_prompt: "You help.", max_steps: 5
    )
    # 25 active messages — 5 will be compacted, 20 kept
    25.times do |i|
      @chat.messages.create!(role: i.even? ? "user" : "assistant",
                             content: "message #{i}", output_tokens: 50)
    end
  end

  test "archives oldest messages, keeps last 20" do
    stub_compaction_llm("Summary.") do
      Daan::CompactConversation.call(@chat, @agent)
    end
    assert_equal 5, Message.where(chat_id: @chat.id).where.not(compacted_message_id: nil).count
  end

  test "broadcasts remove for each archived message" do
    archived_ids = Message.active.where(chat_id: @chat.id).order(:id).first(5).map(&:id)

    stub_compaction_llm("Summary.") do
      assert_broadcasts("chat_#{@chat.id}", 6) do  # 1 summary append + 5 removes
        Daan::CompactConversation.call(@chat, @agent)
      end
    end
  end

  test "summary message has role assistant and correct content" do
    stub_compaction_llm("Here is the summary.") do
      Daan::CompactConversation.call(@chat, @agent)
    end
    summary_id = Message.where(chat_id: @chat.id).where.not(compacted_message_id: nil)
                        .pick(:compacted_message_id)
    summary = Message.find(summary_id)
    assert_equal "assistant", summary.role
    assert_equal "Here is the summary.", summary.content
  end

  test "does nothing when there is nothing to compact (<=20 messages)" do
    @chat.messages.where(compacted_message_id: nil).delete_all
    10.times { |i| @chat.messages.create!(role: "user", content: "msg #{i}", output_tokens: 50) }

    stub_compaction_llm("Should not be called.") do
      Daan::CompactConversation.call(@chat, @agent)
    end
    assert_not Message.where(chat_id: @chat.id).where.not(compacted_message_id: nil).exists?
  end

  test "skips messages with nil content when building compaction prompt" do
    @chat.messages.where(compacted_message_id: nil).delete_all
    25.times do |i|
      @chat.messages.create!(role: i.even? ? "user" : "assistant",
                             content: i == 0 ? nil : "message #{i}", output_tokens: 50)
    end

    captured_ask_arg = nil
    fake_chat = Object.new
    fake_chat.define_singleton_method(:with_model) { |_| fake_chat }
    fake_chat.define_singleton_method(:with_instructions) { |_| fake_chat }
    fake_chat.define_singleton_method(:with_tools) { |*_| fake_chat }
    fake_chat.define_singleton_method(:ask) do |text|
      captured_ask_arg = text
      OpenStruct.new(content: "Summary.")
    end

    RubyLLM.stub(:chat, fake_chat) do
      Daan::CompactConversation.call(@chat, @agent)
      assert captured_ask_arg, "ask should have been called"
      # message 0 has nil content — it must not appear in the prompt
      assert_not_includes captured_ask_arg, "message 0"
      # messages with real content are present
      assert_includes captured_ask_arg, "message 1"
    end
  end

  private

  def stub_compaction_llm(summary_text)
    fake_chat = Object.new
    fake_chat.define_singleton_method(:with_model) { |_| fake_chat }
    fake_chat.define_singleton_method(:with_instructions) { |_| fake_chat }
    fake_chat.define_singleton_method(:with_tools) { |*_| fake_chat }
    fake_chat.define_singleton_method(:ask) { |_| OpenStruct.new(content: summary_text) }
    RubyLLM.stub(:chat, fake_chat) { yield }
  end
end
