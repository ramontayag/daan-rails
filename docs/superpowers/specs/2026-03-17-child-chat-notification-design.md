# Child Chat Notification Design

## Problem

When a child chat (e.g. Engineering Manager) runs out of turns and goes `blocked`, the parent chat (e.g. Chief of Staff) is never notified. The parent keeps saying "still waiting" and the user gets no status update. This happened in chat 25: the EM investigated a git issue, discovered the branch wasn't pushed, but hit max_turns without calling `report_back`. The CoS had nothing to relay.

## Changes

### 1. Two-turns-remaining warning

In `ConversationRunner.finish_conversation`, after incrementing `turn_count`, if there are exactly **3** turns remaining and the chat has a `parent_chat`, inject an invisible user message into the chat itself:

```
[System] You have 2 turns of work remaining before this thread is blocked.
Call report_back now with your current findings.
```

**Why 3 remaining, not 2**: `finish_conversation` runs *after* `run_llm` completes. The injected message sits in history for the *next* `ConversationRunner.call` invocation. So injecting when 3 remain means the LLM sees it with 2 actual turns of work left.

Use `chat.messages.create!(role: "user", content: ..., visible: false)` — not `CreateMessage.call`, so no `LlmJob` enqueue. The message just sits in history for the next turn's context.

Only inject the warning for chats that have a `parent_chat` (i.e. delegated chats with `report_back` available). Top-level chats (CoS) have no one to report to.

**Why user role, not system or assistant:**
- System messages get partitioned out by RubyLLM and merged into the system prompt — loses positional timing.
- Assistant messages are treated as the model's own prior output — the model doesn't respond to its own statements.
- User messages are prompts the model must respond to — the natural fit.

**Note on "invisible"**: `visible: false` means the Message record is not rendered in the UI. The `[System]` prefix is content formatting so the LLM knows it's not from a human or another agent.

### 2. Auto-notify parent on blocked/failed

When a child chat transitions to `blocked` or `failed`, if it has a `parent_chat`, send an invisible user message to the **parent** chat via `CreateMessage.call`:

```
[System] {Agent Display Name}'s thread is now {blocked/failed}.
{If blocked: "They reached the maximum turn limit of {max_turns}."}
{If failed: "An error occurred during execution."}
Their last message: {truncated last assistant message content, max 500 chars, or "No response recorded." if nil}
```

`CreateMessage.call` enqueues `LlmJob.perform_later` on the parent, waking the parent agent to process the notification.

**Two code paths for this:**
- `finish_conversation` handles the `blocked` transition (max turns reached).
- `run_llm` rescue handles the `failed` transition (exception during LLM call). Both must notify the parent.

Extract the notification logic into a private `notify_parent_of_termination` method called from both paths.

**Concurrency**: `LlmJob` has `limits_concurrency to: 1, key: ->(chat) { "chat_#{chat.id}" }`, so if the parent is already processing, the notification job queues behind it. `start_conversation` calls `chat.continue! if chat.may_continue?` before `chat.start! if chat.may_start?` — if the parent is still `in_progress`, neither fires, but the LLM call proceeds fine since the chat is already in the right state.

### 3. Prompt tweak in autonomy partial

Add to `partials/autonomy.md`:

> **Reporting back**: If you have a `report_back` tool, send interim reports as you make progress rather than waiting until everything is done. Don't risk running out of turns with nothing reported.

Light reinforcement — the system injection is the real safety net.

### 4. Max turns: 10 to 15

Change `max_turns` from 10 to 15 in: `chief_of_staff.md`, `engineering_manager.md`, and `agent_resource_manager.md`. (Developer already has 15.)

## Files to modify

| File | Change |
|------|--------|
| `lib/daan/conversation_runner.rb` | Add `notify_parent_of_termination` method; call from `finish_conversation` (blocked) and `run_llm` rescue (failed); add 2-turn warning in `finish_conversation` |
| `lib/daan/core/agents/partials/autonomy.md` | Add reporting-back guidance |
| `lib/daan/core/agents/chief_of_staff.md` | `max_turns: 10` to `max_turns: 15` |
| `lib/daan/core/agents/engineering_manager.md` | `max_turns: 10` to `max_turns: 15` |
| `lib/daan/core/agents/agent_resource_manager.md` | `max_turns: 10` to `max_turns: 15` |

## Testing

- Unit test: `finish_conversation` with a child chat where `turn_count` reaches `max_turns - 3` after increment — verify invisible user message created in the chat with warning text.
- Unit test: `finish_conversation` with a child chat that transitions to `blocked` — verify invisible user message created in parent chat with agent name and last message snippet.
- Unit test: `run_llm` rescue path with a child chat that transitions to `failed` — verify invisible user message created in parent chat.
- Unit test: top-level chat (no parent) that goes blocked — verify no parent notification attempted.
- Unit test: child chat's last assistant message is nil — verify fallback text "No response recorded." in parent notification.
