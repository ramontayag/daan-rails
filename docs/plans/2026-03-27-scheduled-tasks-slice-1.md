# Scheduled Tasks Slice 1: Datetime Injection — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Inject the current datetime into every conversation's LLM context so all agents always know what time it is.

**Architecture:** A new service `Daan::Chats::InjectDatetime` creates a `visible: false`, `role: "user"` message containing the current day, date, time, and UTC offset before the first LLM call in every conversation. `ConversationRunner` calls `InjectDatetime.call(chat)` immediately before `Chats::ConfigureLlm.call` so the message lands in the chat history and is visible to the LLM. The injection is idempotent: it only fires when the chat has no prior datetime injection marker, preventing duplicate messages on re-triggered or multi-step conversations.

**Tech Stack:** Rails 8.1, Minitest

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `lib/daan/chats/inject_datetime.rb` | Service that prepends the datetime context message |
| Create | `test/lib/daan/chats/inject_datetime_test.rb` | Unit tests for `InjectDatetime` |
| Modify | `lib/daan/conversation_runner.rb` | Call `Chats::InjectDatetime.call(chat)` before `ConfigureLlm` |
| Modify | `test/lib/daan/conversation_runner_test.rb` | Integration test asserting datetime message is present |

---

### Task 1: `Daan::Chats::InjectDatetime` service

**Files:**
- Create: `lib/daan/chats/inject_datetime.rb`
- Create: `test/lib/daan/chats/inject_datetime_test.rb`

- [ ] **Step 1: Write failing tests**

Create `test/lib/daan/chats/inject_datetime_test.rb`:

```ruby
# test/lib/daan/chats/inject_datetime_test.rb
require "test_helper"

class Daan::Chats::InjectDatetimeTest < ActiveSupport::TestCase
  setup do
    @agent = Daan::Agent.new(
      name: "test_agent", display_name: "Test Agent",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You are a test agent.",
      max_steps: 3
    )
    Daan::AgentRegistry.register(@agent)
    @chat = Chat.create!(agent_name: "test_agent")
  end

  test "creates a user message with visible: false" do
    Daan::Chats::InjectDatetime.call(@chat)

    msg = @chat.messages.order(:id).last
    assert_equal "user", msg.role
    assert_equal false, msg.visible
  end

  test "message content includes the day of week" do
    travel_to Time.new(2026, 3, 27, 14, 30, 0, "+00:00") do
      Daan::Chats::InjectDatetime.call(@chat)
    end

    msg = @chat.messages.order(:id).last
    assert_includes msg.content, "Friday"
  end

  test "message content includes the full date" do
    travel_to Time.new(2026, 3, 27, 14, 30, 0, "+00:00") do
      Daan::Chats::InjectDatetime.call(@chat)
    end

    msg = @chat.messages.order(:id).last
    assert_includes msg.content, "March 27, 2026"
  end

  test "message content includes the time" do
    travel_to Time.new(2026, 3, 27, 14, 30, 0, "+00:00") do
      Daan::Chats::InjectDatetime.call(@chat)
    end

    msg = @chat.messages.order(:id).last
    assert_includes msg.content, "14:30"
  end

  test "message content includes UTC offset" do
    travel_to Time.new(2026, 3, 27, 14, 30, 0, "+00:00") do
      Daan::Chats::InjectDatetime.call(@chat)
    end

    msg = @chat.messages.order(:id).last
    assert_includes msg.content, "+00:00"
  end

  test "does not inject a second message when called again on the same chat" do
    Daan::Chats::InjectDatetime.call(@chat)
    Daan::Chats::InjectDatetime.call(@chat)

    datetime_messages = @chat.messages.where(
      role: "user",
      visible: false
    ).select { |m| m.content.include?("[System] Current datetime:") }

    assert_equal 1, datetime_messages.size
  end

  test "injects on a chat that already has visible user messages" do
    @chat.messages.create!(role: "user", content: "Hello agent", visible: true)

    assert_difference -> { @chat.messages.where(visible: false).count }, 1 do
      Daan::Chats::InjectDatetime.call(@chat)
    end
  end
end
```

- [ ] **Step 2: Run tests — confirm they all fail**

```
bin/rails test test/lib/daan/chats/inject_datetime_test.rb
```

Expected: 6 errors/failures (constant `Daan::Chats::InjectDatetime` missing).

- [ ] **Step 3: Implement `Daan::Chats::InjectDatetime`**

Create `lib/daan/chats/inject_datetime.rb`:

```ruby
# lib/daan/chats/inject_datetime.rb
module Daan
  module Chats
    class InjectDatetime
      MARKER = "[System] Current datetime:"

      def self.call(chat)
        return if already_injected?(chat)

        now = Time.current
        content = "#{MARKER} #{now.strftime("%A, %B %-d, %Y at %H:%M %Z (UTC%:z)")}"

        # role: "user" (not "system") matches the convention used for all other
        # invisible injections in this codebase (ripple check, step limit warning, etc.).
        # visible: false keeps it out of the UI.
        chat.messages.create!(role: "user", content: content, visible: false)
      end

      def self.already_injected?(chat)
        chat.messages
            .where(role: "user", visible: false)
            .where(Message.arel_table[:content].matches("#{MARKER}%"))
            .exists?
      end
      private_class_method :already_injected?
    end
  end
end
```

- [ ] **Step 4: Run tests — confirm they all pass**

```
bin/rails test test/lib/daan/chats/inject_datetime_test.rb
```

Expected output: `6 runs, 6 assertions, 0 failures, 0 errors`

- [ ] **Step 5: Commit**

```
git add lib/daan/chats/inject_datetime.rb test/lib/daan/chats/inject_datetime_test.rb
git commit -m "$(cat <<'EOF'
feat: add InjectDatetime service to prepend current datetime context

Creates a visible:false user message with day, date, time, and UTC offset
before the first LLM call, with idempotency guard against re-injection.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Wire `InjectDatetime` into `ConversationRunner`

**Files:**
- Modify: `lib/daan/conversation_runner.rb`
- Modify: `test/lib/daan/conversation_runner_test.rb`

- [ ] **Step 1: Write failing test**

Add the following test inside `Daan::ConversationRunnerTest` in `test/lib/daan/conversation_runner_test.rb`, after the existing `"transitions to completed"` test:

```ruby
test "injects a datetime context message before the LLM call" do
  with_stub_step { Daan::ConversationRunner.call(@chat) }

  datetime_msg = @chat.messages.find { |m| m.content&.include?("[System] Current datetime:") }
  assert datetime_msg, "expected a datetime injection message"
  assert_equal "user", datetime_msg.role
  assert_equal false, datetime_msg.visible
end
```

- [ ] **Step 2: Run test — confirm it fails**

```
bin/rails test test/lib/daan/conversation_runner_test.rb
```

Expected: 1 new failure — `expected a datetime injection message` assertion fails.

- [ ] **Step 3: Make two targeted edits to `ConversationRunner`**

**Edit 1 — add the `InjectDatetime` call** between `PrepareWorkspace` and `EnqueueCompaction` in `lib/daan/conversation_runner.rb`:

```ruby
      Chats::PrepareWorkspace.call(agent)
      Chats::InjectDatetime.call(chat)        # ← add this line
      Chats::EnqueueCompaction.call(chat)
```

**Edit 2 — fix `already_responded?`** to filter to visible user messages only. The injected datetime message has `role: "user", visible: false`. Without this fix, `already_responded?` would treat the datetime injection as "the last user message", causing `context_user_message_id >= last_user_message.id` to evaluate false (since the datetime message has a higher ID than the real user message), breaking the duplicate-processing guard.

In the `already_responded?` method, change the first line:

```ruby
# Before:
last_user_message = chat.messages.where(role: "user").last

# After:
last_user_message = chat.messages.where(role: "user", visible: true).last
```

- [ ] **Step 4: Run full `ConversationRunnerTest` — confirm all pass**

```
bin/rails test test/lib/daan/conversation_runner_test.rb
```

Expected: all existing tests plus the new one pass, 0 failures.

- [ ] **Step 5: Commit**

```
git add lib/daan/conversation_runner.rb test/lib/daan/conversation_runner_test.rb
git commit -m "$(cat <<'EOF'
feat: wire InjectDatetime into ConversationRunner before LLM call

Calls Chats::InjectDatetime.call(chat) after PrepareWorkspace so the
datetime context message is in the chat history before ConfigureLlm
configures the model for the step.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Full test suite green check

- [ ] **Step 1: Run the full test suite**

```
bin/rails test && bin/rails test:system
```

Expected: 0 failures, 0 errors across all unit and system tests.

- [ ] **Step 2: Smoke-test in development**

Start the app (`bin/dev`) and open any agent chat. Send any message. In the Rails console, confirm:

```ruby
Chat.last.messages.where(visible: false).where("content LIKE '[System] Current datetime:%'").first&.content
# => "[System] Current datetime: Friday, March 27, 2026 at 14:30 UTC (+00:00)"
```
