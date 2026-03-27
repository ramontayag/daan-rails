---
shaping: true
---

# Scheduled Tasks — Slices

Based on [scheduled-tasks-shaping-doc.md](scheduled-tasks-shaping-doc.md), selected shape C.

---

## Slice 1: Datetime injection

**Demo:** Start any conversation. The agent knows today's date and time without being told.

| Affordance | Type | Detail |
|------------|------|--------|
| ConversationRunner: datetime injection | Non-UI | Prepends a `visible: false` system message with the current datetime (day, date, time, timezone) before the first LLM call in every conversation |

---

## Slice 2: Recurring scheduled tasks end-to-end

**Demo:** Create a recurring task via the UI targeting an agent with a daily schedule. At the next tick, a new chat thread appears in the agent's history with the "started automatically" system message.

| Affordance | Type | Detail |
|------------|------|--------|
| `ScheduledTask` model | Non-UI | `agent_name`, `message`, `schedule` (cron string), `timezone`, `last_enqueued_at`, `enabled` (boolean, default true) |
| `ScheduledTaskPollerJob` | Non-UI | Registered in `recurring.yml` to run every minute; queries enabled recurring tasks; uses fugit to check if schedule has ticked since `last_enqueued_at`; enqueues `ScheduledTaskRunnerJob` and stamps `last_enqueued_at` if due; at most one fire per window |
| `ScheduledTaskRunnerJob` | Non-UI | Creates a new Chat for the target agent; prepends a `visible: false` system message ("This conversation was started automatically by a scheduled task"); creates the user message from `task.message`; enqueues `LlmJob` |
| Scheduled tasks index | UI | Lists all recurring `ScheduledTask` records: name, agent, schedule, timezone, last fired, enabled toggle |
| New/edit task form | UI | Fields: agent (select), message (textarea), schedule (text, human-readable cron), timezone (hidden, captured from `Intl.DateTimeFormat().resolvedOptions().timeZone` via JS on submit) |
| Delete task | UI | Destroys the record |

---

## Slice 3: One-shot tasks + agent self-scheduling

**Demo:** In a conversation, an agent calls `schedule_task` with a message and a `run_at` 5 minutes from now. The task appears in a separate "Scheduled once" section on the tasks page with a link back to the originating chat. Five minutes later, a new chat thread fires and the task disappears from the active list.

| Affordance | Type | Detail |
|------------|------|--------|
| `ScheduledTask` model (extended) | Non-UI | Adds `task_type` (enum: `recurring`/`one_shot`, default `recurring`), `run_at` (datetime, nullable), `source_chat_id` (FK to `chats`, nullable) |
| `ScheduledTaskPollerJob` (extended) | Non-UI | For one-shot tasks: checks `run_at <= Time.current` and `enabled: true`; enqueues runner if due |
| `ScheduledTaskRunnerJob` (extended) | Non-UI | After enqueueing for a one-shot task: sets `enabled: false` so it never re-fires |
| `schedule_task` agent tool | Non-UI | Registered in the tool registry; accepts `agent_name` (string), `message` (string), `run_at` (ISO8601 string); creates a one-shot `ScheduledTask` with `source_chat_id` set to the current chat's id |
| One-shot section on tasks index | UI | Separate section below recurring tasks listing one-shot tasks: message, target agent, fires at, status (pending/fired); each row links to `source_chat` |
