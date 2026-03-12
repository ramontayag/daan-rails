---
shaping: true
---

# V7: Context Compaction

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Long conversations don't fail when they exceed the model's context window. Before each LLM call, the token count is checked; if it exceeds 80% of the model's context window, a `CompactJob` is enqueued (fire and forget) and the current LLM call proceeds normally with the full context — the agent responds to the user immediately. On the next LLM call, the compacted context is automatically used. Demo: Start a long conversation, send enough messages to trigger compaction, verify the agent responds coherently and the summary message appears in the thread with an archived message count.

**Architecture:**
- `compacted_message_id` — self-referential FK on `messages`. Original messages point to the summary message that replaced them. Summary identity is inferred from `compacted_messages_count > 0` (counter cache — no extra query).
- `Message.scope :active` — `where(compacted_message_id: nil)`. Used by the service, the runner, and the LLM context loader.
- `Chat#order_messages_for_llm` — overrides a private hook defined in `RubyLLM::ActiveRecord::ChatMethods` (`chat_methods.rb`). RubyLLM calls this before every API call; we call `super` then reject archived messages. `chat.messages` stays as the full unscoped association from `acts_as_chat` (owns cascade destroy and direct record access).
- `CompactJob` — thin job, fire-and-forget from `ConversationRunner`. Calls `Daan::CompactConversation.call(chat, chat.agent)`. Same `limits_concurrency` key as `LlmJob`.
- `Daan::CompactConversation` — selects active messages except the last 20, makes a separate in-memory RubyLLM call with OpenCode-style prompt + SwarmMemory write/edit tools, creates the summary via `Daan::CreateMessage`, and archives old messages via `update_all`.
- Trigger — `ConversationRunner` enqueues `CompactJob` if token sum exceeds 80% of context window. Current LLM call continues with full context. Next call sees the compacted context automatically.
- Token estimate — `SUM(COALESCE(output_tokens, LENGTH(content) / 4, 0))` across active messages. Integer division is intentional — rough estimate, 80% threshold has headroom.

**Not in V7:** Streaming compaction progress to UI, per-agent `keep_recent` override (20 is the default), automatic compaction retry (CompactJob fails independently; next LlmJob re-checks and re-enqueues if still needed), originals page (read-only view of archived messages — deferred to V8).

**Tech Stack:** Rails 8.1, RubyLLM (in-memory chat for compaction call), SwarmMemory (write/edit tools), Solid Queue, Minitest

---

## Implementation Plan

### Task 1: Migration + Chat/Message model

Add `compacted_message_id` and `compacted_messages_count` to messages. Wire the self-referential associations on `Message` with a counter cache. Add `Message.scope :active`. Override `Chat#order_messages_for_llm` to filter archived messages from every API call.

**Files:**
- Create: `db/migrate/TIMESTAMP_add_compacted_message_id_to_messages.rb`
- Modify: `app/models/message.rb`
- Modify: `app/models/chat.rb`
- Create: `test/models/message_compaction_test.rb`

**Step 1: Write failing tests**

```ruby
# test/models/message_compaction_test.rb
require "test_helper"

class MessageCompactionTest < ActiveSupport::TestCase
  setup do
    @chat = chats(:one)
    # Use chat.messages (full association) to create all records directly
    @summary  = @chat.messages.create!(role: "assistant", content: "Summary of earlier work.")
    @original1 = @chat.messages.create!(role: "user",      content: "original 1",
                                        compacted_message_id: @summary.id)
    @original2 = @chat.messages.create!(role: "assistant", content: "original 2",
                                        compacted_message_id: @summary.id)
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
    chat = chats(:one)
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
```

**Step 2: Run to confirm failures**

```
bin/rails test test/models/message_compaction_test.rb
```

**Step 3: Generate migration**

```
bin/rails generate migration AddCompactedMessageIdToMessages compacted_message_id:integer
```

Edit the generated migration to add an index and foreign key:

```ruby
def change
  add_column :messages, :compacted_message_id, :integer
  add_column :messages, :compacted_messages_count, :integer, default: 0, null: false
  add_index :messages, :compacted_message_id
  add_foreign_key :messages, :messages, column: :compacted_message_id
end
```

```
bin/rails db:migrate
```

**Step 4: Update Message model**

```ruby
class Message < ApplicationRecord
  acts_as_message tool_calls_foreign_key: :message_id

  belongs_to :compacted_message, class_name: "Message", optional: true,
                                 counter_cache: :compacted_messages_count
  has_many :compacted_messages, class_name: "Message", foreign_key: :compacted_message_id,
                                inverse_of: :compacted_message

  scope :active, -> { where(compacted_message_id: nil) }

  def summary? = compacted_messages_count > 0
end
```

**Step 5: Update Chat model**

Add one private method after `acts_as_chat`. Do not redefine the `messages` association — it stays as the full unscoped set (owns `dependent: :destroy`).

```ruby
private

# RubyLLM calls this private hook (defined in RubyLLM::ActiveRecord::ChatMethods,
# chat_methods.rb) before every API call. We call super first so RubyLLM can apply
# its own ordering, then reject archived originals so they are never sent to the API.
# Overriding this hook keeps chat.messages a clean, unscoped Rails association.
def order_messages_for_llm(messages)
  super(messages.reject { |m| m.compacted_message_id.present? })
end
```

**Step 6: Run tests**

```
bin/rails test test/models/message_compaction_test.rb
```

Expected: all pass.

**Step 7: Run full suite**

```
bin/rails test
```

**Step 8: Commit**

```bash
git add db/migrate/*_add_compacted_message_id_to_messages.rb \
        db/schema.rb \
        app/models/message.rb \
        app/models/chat.rb \
        test/models/message_compaction_test.rb
git commit -m "feat: compacted_message_id on messages — self-referential FK for context compaction"
```

---

### Task 2: `Daan::CompactConversation` service

Selects active messages to compact, calls LLM with an OpenCode-style compaction prompt equipped with SwarmMemory write/edit tools, creates the summary via `CreateMessage`, and archives the originals.

**Files:**
- Create: `lib/daan/compact_conversation.rb`
- Create: `test/lib/daan/compact_conversation_test.rb`

**Step 1: Write failing tests**

```ruby
# test/lib/daan/compact_conversation_test.rb
require "test_helper"

class Daan::CompactConversationTest < ActiveSupport::TestCase
  setup do
    @chat = chats(:one)
    @agent = Daan::Agent.new(
      name: "test", display_name: "Test",
      model_name: "claude-haiku-4-5-20251001",
      system_prompt: "You help.", max_turns: 5
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

    captured_prompt = nil
    stub_compaction_llm("Summary.") do
      Daan::CompactConversation.stub(:generate_summary, ->(msgs, _agent) {
        captured_prompt = msgs.map(&:content).compact.join
        "Summary."
      }) do
        Daan::CompactConversation.call(@chat, @agent)
      end
    end

    assert captured_prompt, "prompt should have been captured"
    assert_not_includes captured_prompt.split("\n"), ""
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
```

**Step 2: Run to confirm failures**

```
bin/rails test test/lib/daan/compact_conversation_test.rb
```

**Step 3: Implement `Daan::CompactConversation`**

```ruby
# lib/daan/compact_conversation.rb
module Daan
  class CompactConversation
    KEEP_RECENT = 20

    SYSTEM_PROMPT = <<~PROMPT.strip
      Your task is to create a comprehensive summary of this conversation so that an agent
      can continue working with full context. Also save key learnings to shared memory
      using your memory tools — update existing entries if they conflict rather than
      creating duplicates.

      Structure your summary using this template:

      ## Goal
      [What task or goal was being pursued?]

      ## Instructions
      [What important instructions or constraints were established?]

      ## Discoveries
      [What notable things were learned during this conversation?]

      ## Accomplished
      [What work has been completed? What is still in progress or pending?]

      ## Key Context
      [Important facts, decisions, file paths, or references needed to continue]
    PROMPT

    def self.call(chat, agent, keep_recent: KEEP_RECENT)
      active = Message.active.where(chat_id: chat.id).order(:id).to_a
      to_compact = active[0..-(keep_recent + 1)]
      return if to_compact.blank?

      summary_text = generate_summary(to_compact, agent)
      summary = Daan::CreateMessage.call(chat, role: "assistant", content: summary_text)
      Message.where(id: to_compact.map(&:id)).update_all(compacted_message_id: summary.id)
      # update_all bypasses callbacks so the counter cache needs a manual reset
      Message.reset_counters(summary.id, :compacted_messages)

      summary
    end

    def self.generate_summary(messages, agent)
      storage = Daan::Memory.storage
      memory_tools = [
        SwarmMemory::Tools::MemoryWrite.new(storage: storage),
        SwarmMemory::Tools::MemoryEdit.new(storage: storage)
      ]

      # Filter nil content (tool-call-only messages have no text to summarise)
      conversation_text = messages
        .select { |m| m.content.present? }
        .map { |m| "[#{m.role}]: #{m.content}" }
        .join("\n\n")

      RubyLLM.chat
        .with_model(agent.model_name)
        .with_instructions(SYSTEM_PROMPT)
        .with_tools(*memory_tools)
        .ask("Please summarize the following conversation:\n\n#{conversation_text}")
        .content
    end
    private_class_method :generate_summary
  end
end
```

**Step 4: Run tests**

```
bin/rails test test/lib/daan/compact_conversation_test.rb
```

**Step 5: Run full suite**

```
bin/rails test
```

**Step 6: Commit**

```bash
git add lib/daan/compact_conversation.rb \
        test/lib/daan/compact_conversation_test.rb
git commit -m "feat: CompactConversation service — summarise old messages, archive originals, write memories"
```

---

### Task 3: `CompactJob`

Thin job wrapper around `CompactConversation`. Uses the same concurrency key as `LlmJob` so it never runs concurrently with an LLM call for the same chat.

**Files:**
- Create: `app/jobs/compact_job.rb`
- Create: `test/jobs/compact_job_test.rb`

**Step 1: Write failing test**

```ruby
# test/jobs/compact_job_test.rb
require "test_helper"

class CompactJobTest < ActiveJob::TestCase
  test "calls CompactConversation with chat and agent" do
    chat = chats(:one)
    called_with = nil

    Daan::CompactConversation.stub(:call, ->(c, a) { called_with = [c, a] }) do
      CompactJob.perform_now(chat)
    end

    assert_equal chat, called_with[0]
    assert_equal chat.agent, called_with[1]
  end
end
```

**Step 2: Run to confirm failure**

```
bin/rails test test/jobs/compact_job_test.rb
```

**Step 3: Implement CompactJob**

```ruby
# app/jobs/compact_job.rb
class CompactJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: ->(chat) { "chat_#{chat.id}" }

  def perform(chat)
    Daan::CompactConversation.call(chat, chat.agent)
  end
end
```

**Step 4: Run tests**

```
bin/rails test test/jobs/compact_job_test.rb
```

**Step 5: Run full suite**

```
bin/rails test
```

**Step 6: Commit**

```bash
git add app/jobs/compact_job.rb test/jobs/compact_job_test.rb
git commit -m "feat: CompactJob — thin job wrapper for CompactConversation with per-chat concurrency lock"
```

---

### Task 4: Trigger compaction in ConversationRunner

Enqueue `CompactJob` (fire and forget) when active messages exceed 80% of the model's context window. The current LLM call continues immediately — the agent responds to the user. On the next call, `order_messages_for_llm` automatically filters out the archived originals.

**Files:**
- Modify: `lib/daan/conversation_runner.rb`
- Modify: `test/lib/daan/conversation_runner_test.rb`

**Step 1: Write failing tests**

```ruby
# test/lib/daan/conversation_runner_test.rb — add
test "enqueues CompactJob when token count exceeds 80% of context window" do
  @chat.messages.where(compacted_message_id: nil).delete_all
  25.times do |i|
    @chat.messages.create!(role: i.even? ? "user" : "assistant",
                           content: "message #{i}", output_tokens: 40)
  end
  # 25 * 40 = 1000 tokens; 80% of 1000 = 800 → triggers compaction

  @chat.stub(:model, OpenStruct.new(context_window: 1000)) do
    assert_enqueued_with(job: CompactJob) do
      with_stub_complete { Daan::ConversationRunner.call(@chat) }
    end
  end
end

test "does not enqueue CompactJob when token count is below threshold" do
  @chat.messages.where(compacted_message_id: nil).delete_all
  @chat.messages.create!(role: "user", content: "hi", output_tokens: 10)

  @chat.stub(:model, OpenStruct.new(context_window: 1000)) do
    assert_no_enqueued_jobs(only: CompactJob) do
      with_stub_complete { Daan::ConversationRunner.call(@chat) }
    end
  end
end
```

**Step 2: Run to confirm failures**

```
bin/rails test test/lib/daan/conversation_runner_test.rb
```

**Step 3: Add `enqueue_compaction_if_needed` to ConversationRunner**

Add the call after `prepare_workspace`, before `configure_llm`. The job is enqueued and the runner continues immediately.

```ruby
def self.call(chat)
  agent = chat.agent

  start_conversation(chat)
  prepare_workspace(agent)
  enqueue_compaction_if_needed(chat)
  configure_llm(chat, agent)

  last_message_id = chat.messages.maximum(:id) || 0
  run_llm(chat)

  BroadcastMessagesJob.perform_later(chat, last_message_id)
  broadcast_typing(chat, false)
  finish_conversation(chat, agent)
end

def self.enqueue_compaction_if_needed(chat)
  context_window = chat.model.context_window
  threshold = (context_window * 0.8).to_i
  # Integer division in COALESCE fallback is intentional — rough estimate,
  # 80% threshold provides sufficient headroom.
  token_sum = Message.active
                     .where(chat_id: chat.id)
                     .sum("COALESCE(output_tokens, LENGTH(content) / 4, 0)")
  CompactJob.perform_later(chat) if token_sum >= threshold
end
private_class_method :enqueue_compaction_if_needed
```

**Step 4: Run tests**

```
bin/rails test test/lib/daan/conversation_runner_test.rb
```

**Step 5: Run full suite**

```
bin/rails test
```

**Step 6: Commit**

```bash
git add lib/daan/conversation_runner.rb \
        test/lib/daan/conversation_runner_test.rb
git commit -m "feat: enqueue CompactJob fire-and-forget when token sum exceeds 80% of context window"
```

---

### Task 5: UI — summary message in thread

Summary messages render with a count badge showing how many messages were archived. Uses `summary?` (reads `compacted_messages_count` — no query).

**Files:**
- Modify: `app/components/message_component.rb`
- Modify: `app/components/message_component.html.erb`
- Create: `test/components/message_component_compaction_test.rb`

**Step 1: Read the current component files**

Read `message_component.rb` and `message_component.html.erb` before making changes.

**Step 2: Write failing tests**

```ruby
# test/components/message_component_compaction_test.rb
require "test_helper"

class MessageComponentCompactionTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  setup do
    @chat = chats(:one)
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
```

**Step 3: Update MessageComponent**

In `message_component.html.erb`, after the message content block, add:

```erb
<% if message.summary? %>
  <p class="mt-2 text-xs text-gray-400">
    <%= message.compacted_messages_count %> messages archived
  </p>
<% end %>
```

No extra queries — `summary?` and `compacted_messages_count` read the counter cache column directly.

**Step 4: Run tests**

```
bin/rails test test/components/message_component_compaction_test.rb
```

**Step 5: Run full suite**

```
bin/rails test
```

**Step 6: Commit**

```bash
git add app/components/message_component.rb \
        app/components/message_component.html.erb \
        test/components/message_component_compaction_test.rb
git commit -m "feat: render summary message in thread with archived message count"
```

---

### Task 6: UI — originals page _(deferred to V8)_

A read-only page listing the original messages archived into a summary. Route: `resource :compaction, only: [:show], controller: "compacted_messages"` nested under `messages`. Controller raises `ActiveRecord::RecordNotFound` for non-summary messages. Deferred because the V7 demo goal (summary appears in thread, agent stays coherent) doesn't require it.

---

## Demo Script

1. Start the app: `bin/dev`

2. In the console, seed a chat with enough token weight to trigger compaction:
   ```ruby
   chat = Chat.first
   30.times { |i| chat.messages.create!(role: i.even? ? "user" : "assistant", content: "message #{i}", output_tokens: 10_000) }
   ```

3. Send a new message to the CoS. `ConversationRunner` enqueues `CompactJob` and responds to the user immediately.

4. `CompactJob` runs in the background — the summary message appears in the thread via Turbo Stream broadcast from `CreateMessage`.

5. Verify the agent's response is coherent — it answered using the full (pre-compaction) context.

6. Send another message. This time `ConversationRunner` uses the compacted context (summary + recent messages).

7. Switch to another perspective (e.g., Engineering Manager) — confirm their threads are unaffected.
