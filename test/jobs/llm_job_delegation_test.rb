# test/jobs/llm_job_delegation_test.rb
require "test_helper"

class LlmJobDelegationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "CoS calls DelegateTask and creates EM sub-chat" do
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
    chat = Chat.create!(agent_name: "chief_of_staff")
    chat.messages.create!(role: "user",
      content: "Please have the team read the file README.md and summarise it for me.")

    VCR.use_cassette("cos_delegates_to_em") do
      LlmJob.perform_now(chat)
    end

    sub_chat = Chat.find_by(agent_name: "engineering_manager", parent_chat: chat)
    assert_not_nil sub_chat, "Expected EM sub-chat to be created by DelegateTask"
    assert_equal 1, sub_chat.messages.where(role: "user").count
  end
end
