# test/models/document_test.rb
require "test_helper"

class DocumentTest < ActiveSupport::TestCase
  test "is valid with title, body, and chat" do
    doc = Document.new(title: "Plan", body: "# Plan", chat: chats(:hello_cos))
    assert doc.valid?
  end

  test "requires title" do
    doc = Document.new(body: "# Plan", chat: chats(:hello_cos))
    assert_not doc.valid?
  end

  test "requires chat" do
    doc = Document.new(title: "Plan", body: "# Plan")
    assert_not doc.valid?
  end

  test "body can be blank" do
    doc = Document.new(title: "Plan", body: "", chat: chats(:hello_cos))
    assert doc.valid?
  end
end
