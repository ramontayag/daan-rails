require "test_helper"

class CompactJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup do
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
  end

  test "calls CompactConversation with chat and agent" do
    chat = chats(:hello_cos)
    called_with = nil

    sc = Daan::CompactConversation.singleton_class
    sc.alias_method(:__orig_call__, :call)
    sc.define_method(:call) { |c, a| called_with = [ c, a ] }
    begin
      CompactJob.perform_now(chat)
      assert_not_nil called_with, "CompactConversation.call was never invoked"
      assert_equal chat, called_with[0]
      assert_equal chat.agent, called_with[1]
    ensure
      sc.alias_method(:call, :__orig_call__)
      sc.remove_method(:__orig_call__)
    end
  end
end
