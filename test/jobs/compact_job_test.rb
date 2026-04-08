require "test_helper"

class CompactJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup do
    Daan::Core::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
  end

  test "calls CompactConversation with chat and agent" do
    chat = chats(:hello_cos)
    called_with = nil

    Daan::Core::CompactConversation.stub(:call, ->(c, a) { called_with = [ c, a ] }) do
      CompactJob.perform_now(chat)
    end
    assert_not_nil called_with, "CompactConversation.call was never invoked"
    assert_equal chat, called_with[0]
    assert_equal chat.agent, called_with[1]
  end
end
