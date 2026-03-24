require "test_helper"

class MessageTest < ActiveSupport::TestCase
  setup do
    @chat = chats(:hello_cos)
  end

  test "since_id excludes messages at or before the given id" do
    older = @chat.messages.create!(role: "user", content: "older")
    newer = @chat.messages.create!(role: "user", content: "newer")

    results = @chat.messages.since_id(older.id)

    assert_includes results, newer
    assert_not_includes results, older
  end

  test "where_created_at_gt excludes messages at or before the cutoff" do
    old = @chat.messages.create!(role: "user", content: "old message")
    travel 1.second
    new = @chat.messages.create!(role: "user", content: "new message")

    results = @chat.messages.where_created_at_gt(old.created_at)

    assert_includes results, new
    assert_not_includes results, old
  end

  test "where_content_like matches prefix pattern" do
    match    = @chat.messages.create!(role: "user", content: "Engineering Manager: done")
    no_match = @chat.messages.create!(role: "user", content: "Something else entirely")

    results = @chat.messages.where_content_like("Engineering Manager: %")

    assert_includes results, match
    assert_not_includes results, no_match
  end
end
