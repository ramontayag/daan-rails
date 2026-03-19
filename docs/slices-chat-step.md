---
shaping: true
---

# chat.step — Slices

Shaping doc: `docs/shaping-chat-step.md`

---

## Slice 1: Single-step execution

Replace `chat.complete` with `chat.step` + re-enqueue. Agents work identically from the UI — same responses, same broadcasts — but each LLM call is now a separate job.

| Affordance | Change |
|------------|--------|
| `RubyLLM::Chat#step` | Add to RubyLLM fork — one provider call + tool execution, no recursion |
| `ConversationRunner#run_step` | Replace `run_llm` — calls `chat.step`, broadcasts response inline |
| `ConversationRunner#finish_or_reenqueue` | Replace end of `call` — if `response.tool_call?` → `LlmJob.perform_later`; else → `finish_conversation` |
| `BroadcastMessagesJob` | Remove — broadcast now inline in `run_step` |

**Demo:** Send a message to any agent. It responds as before. Under the hood: one job per LLM call, no watermark, no `BroadcastMessagesJob`.

---

## Slice 2: Step limit enforcement

Wire in `step_count` and `max_steps`. Agents get nudged before hitting the limit; parent is notified when they do.

| Affordance | Change |
|------------|--------|
| `Message.assistant` scope + `Message.since_id` | New scopes (Arel) used to derive step_count |
| `Chat#step_count` | Derived: `messages.assistant.since_id(last_visible_user_msg_id).count` |
| Agent YAML: `max_turns` → `max_steps` | Rename in all 4 agent files |
| `Agent#max_steps` | Rename from `max_turns` |
| `ConversationRunner#warn_approaching_step_limit` | Update to use `step_count` / `max_steps` |
| `ConversationRunner#finish_conversation` | Check `step_count >= max_steps` instead of `turn_count >= max_turns` |
| Migration: drop `turn_count` | Column no longer needed |

**Demo:** Let an agent run a tool-heavy task until it hits `max_steps`. UI shows agent blocked. Parent chat receives the termination notification.
