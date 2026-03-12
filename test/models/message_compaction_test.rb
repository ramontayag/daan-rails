require "test_helper"

class MessageCompactionTest < ActiveSupport::TestCase
  setup do
    @chat = chats(:hello_cos)
    # Use chat.messages (full association) to create all records directly
    @summary  = @chat.messages.create!(role: "assistant", content: "Summary of earlier work.")
    @original1 = @chat.messages.create!(role: "user",      content: "original 1",
                                        compacted_message_id: @summary.id)
    @original2 = @chat.messages.create!(role: "assistant", content: "original 2",
                                        compacted_message_id: @summary.id)
    @summary.reload
  end

  test "summary? is true when message has compacted_messages" do
    assert @summary.summary?
  end

  test "summary? is false for regular messages" do
    regular = @chat.messages.create!(role: "user", content: "hi")
    refute regular.summary?
  end

  test "compacted_messages returns originals" do
    assert_includes @summary.compacted_messages, @original1
    assert_includes @summary.compacted_messages, @original2
  end

  test "Message.active excludes compacted originals" do
    active_ids = Message.active.where(chat_id: @chat.id).pluck(:id)
    refute_includes active_ids, @original1.id
    refute_includes active_ids, @original2.id
  end

  test "Message.active includes summary" do
    assert_includes Message.active.where(chat_id: @chat.id).pluck(:id), @summary.id
  end

  test "chat.messages includes everything (unscoped)" do
    all_ids = @chat.messages.pluck(:id)
    assert_includes all_ids, @summary.id
    assert_includes all_ids, @original1.id
    assert_includes all_ids, @original2.id
  end

  # We appear to be testing a RubyLLM private method here, but we are not.
  # We are testing OUR override of Chat#order_messages_for_llm, a private hook
  # defined in RubyLLM::ActiveRecord::ChatMethods (chat_methods.rb). If RubyLLM
  # renames or removes this hook, archived messages will silently leak to the API —
  # this test catches that regression by asserting at the HTTP boundary, not by
  # testing RubyLLM's internals directly.
  test "chat.complete does not send archived messages to the Anthropic API" do
    chat = chats(:hello_cos)
    chat.with_model("claude-haiku-4-5-20251001").with_instructions("test")

    summary   = chat.messages.create!(role: "assistant", content: "Summary.")
    _archived = chat.messages.create!(role: "user", content: "archived content",
                                      compacted_message_id: summary.id)
    _active   = chat.messages.create!(role: "user", content: "active content")

    sent_body = nil
    stub_request(:post, /api\.anthropic\.com/)
      .to_return do |req|
        sent_body = JSON.parse(req.body)
        { status: 200, headers: { "Content-Type" => "application/json" },
          body: fake_anthropic_response }
      end

    chat.complete

    message_contents = sent_body["messages"].map { |m|
      Array(m["content"]).map { |c| c.is_a?(Hash) ? c["text"] : c }
    }.flatten.join
    assert_includes     message_contents, "active content"
    assert_not_includes message_contents, "archived content"
  end
end
