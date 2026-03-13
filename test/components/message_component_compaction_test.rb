require "test_helper"

class MessageComponentCompactionTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  setup do
    @chat = chats(:hello_cos)
    @summary = @chat.messages.create!(role: "assistant", content: "Summary of earlier work.")
    3.times { |i| @chat.messages.create!(role: "user", content: "original #{i}",
                                         compacted_message_id: @summary.id) }
    Message.reset_counters(@summary.id, :compacted_messages)
    @summary.reload
  end

  test "renders archived message count for summary message" do
    render_inline(MessageComponent.new(message: @summary))
    assert_includes rendered_content, "3 messages archived"
  end

  test "does not render archived count for regular message" do
    regular = @chat.messages.create!(role: "user", content: "hi")
    render_inline(MessageComponent.new(message: regular))
    assert_not_includes rendered_content, "messages archived"
  end
end
