# test/lib/daan/chats/enqueue_compaction_test.rb
require "test_helper"
require "ostruct"

class Daan::Chats::EnqueueCompactionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Daan::AgentRegistry.register(
      Daan::Agent.new(
        name: "test_agent", display_name: "Test Agent",
        model_name: "claude-sonnet-4-20250514",
        system_prompt: "You are a test agent.", max_steps: 3
      )
    )
    @chat = Chat.create!(agent_name: "test_agent")
    @chat.messages.where(compacted_message_id: nil).delete_all
    @chat.define_singleton_method(:model) { OpenStruct.new(context_window: 1000) }
  end

  teardown do
    if @chat.singleton_class.method_defined?(:model, false)
      @chat.singleton_class.remove_method(:model)
    end
  end

  test "enqueues CompactJob when token count exceeds 80% of context window" do
    25.times do |i|
      @chat.messages.create!(role: i.even? ? "user" : "assistant",
                             content: "message #{i}", output_tokens: 40)
    end
    # 25 * 40 = 1000 tokens; 80% of 1000 = 800 → triggers compaction

    assert_enqueued_with(job: CompactJob) do
      Daan::Chats::EnqueueCompaction.call(@chat)
    end
  end

  test "does not enqueue CompactJob when token count is below threshold" do
    @chat.messages.create!(role: "user", content: "hi", output_tokens: 10)

    assert_no_enqueued_jobs(only: CompactJob) do
      Daan::Chats::EnqueueCompaction.call(@chat)
    end
  end
end
