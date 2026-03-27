---
shaping: true
---

## Frame

**Problem:** There's no way to have an agent do something automatically on a schedule. Everything requires manually starting a conversation.

**Outcome:** You can define scheduled tasks that fire a synthetic user message into a new agent thread at a configured time, as if you had started the conversation yourself.

---

## Requirements

| Req | Requirement | Status |
|-----|-------------|--------|
| R0 | Scheduled tasks fire a synthetic user message into a new thread with a specified agent, on a schedule | Core goal |
| R1 | Each task targets a specific agent (e.g. Chief of Staff) | Core goal |
| 🟡 R2 | A system message is prepended to the thread noting it was started automatically by a scheduled task | Must-have |
| R3 | Each task runs on a human-readable schedule (e.g. "every day at 8am") | Must-have |
| R4 | Tasks can be created, edited, and deleted frequently | Must-have |
| R5 | Tasks are manageable via a new UI surface | Must-have |
| R6 | Silent failure is acceptable — no error alerting needed | Must-have |
| R7 | Browser timezone is captured when a task is created/edited and stored on the task; schedule runs in that timezone | Must-have |
| R8 | Scheduling uses Solid Queue infrastructure, not a system cron daemon | Must-have |
| R9 | The app should not depend on Solid Queue's internal AR model schema for core business logic | Must-have |
| R10 | Notifications are out of scope | Out |
| R11 | If the server was down when a task was due, it fires once when the server comes back (at most one fire per schedule window — the latest) | Must-have |
| R12 | An agent can create a scheduled task programmatically during a conversation via a tool call (not UI-only) | Must-have |
| R13 | Tasks can be one-shot (fire once at a specified time, then auto-expire) — needed for agent-initiated patterns like "check CI in 5 minutes" | Must-have |
| R14 | One-shot tasks appear in a separate section on the scheduled tasks UI page, with a link to the originating chat | Must-have |
| 🟡 R15 | The current datetime is injected into the LLM context for every conversation, so all agents always know what time it is | Must-have |

---

## Selected Shape

**C: Poller — one static job checks ScheduledTask table every minute**

One static entry in `recurring.yml` fires a `ScheduledTaskPollerJob` every minute. It queries all active `ScheduledTask` records, uses fugit to determine if the schedule has ticked since `last_enqueued_at`. If yes, it enqueues `ScheduledTaskRunnerJob` for that task and stamps `last_enqueued_at`. At most one fire per schedule window — if multiple ticks were missed (e.g. server was down), only the latest fires.

### Why C over A and B

- Simpler than A — no sync logic between two models
- Avoids coupling to Solid Queue internals (fails R9) unlike B
- ~1 minute accuracy is fine for the use case
- fugit is already in the stack (Solid Queue dependency)

---

## Parts

| Part | Mechanism | Flag |
|------|-----------|:----:|
| **C1** | `ScheduledTask` model — stores `agent_name`, `message`, `schedule` (cron string), `timezone`, `last_enqueued_at`, `enabled`; adds `run_at` (timestamp, one-shot), `task_type` (enum: `recurring`/`one_shot`), `source_chat_id` (FK to originating Chat, nullable) | |
| **C2** | `ScheduledTaskPollerJob` — static recurring job (every minute in `recurring.yml`), queries `ScheduledTask`; for recurring: uses fugit to check if schedule has ticked since `last_enqueued_at`; for one-shot: checks if `run_at <= now` and not yet fired; enqueues runner if due | |
| **C3** | `ScheduledTaskRunnerJob` — creates a new Chat for the agent, prepends a system message noting the conversation was started automatically, creates the user message, enqueues `LlmJob`; for one-shot tasks: marks `enabled: false` after enqueueing so the task never re-fires | |
| **C4** | Schedule UI — new surface to list, create, edit, delete `ScheduledTask` records; captures browser timezone on create/edit via JS; one-shot tasks shown in a separate section with a link to `source_chat` | |
| **C5** | Agent tool `schedule_task` — exposed to the LLM via the tool registry; accepts `agent_name`, `message`, `run_at` (ISO8601); creates a one-shot `ScheduledTask` with `source_chat_id` set to the current chat | |
| 🟡 **C6** | `ConversationRunner` datetime injection — prepends the current datetime to the system context for every conversation, not just scheduled tasks | |

---

## Fit Check (R × C)

| Req | Requirement | Status | C |
|-----|-------------|--------|---|
| R0 | Scheduled tasks fire a synthetic user message into a new thread with a specified agent, on a schedule | Core goal | ✅ |
| R1 | Each task targets a specific agent | Core goal | ✅ |
| R2 | A system message is prepended noting the conversation was started automatically | Must-have | ✅ |
| R3 | Each task runs on a human-readable schedule (e.g. "every day at 8am") | Must-have | ✅ |
| R4 | Tasks can be created, edited, and deleted frequently | Must-have | ✅ |
| R5 | Tasks are manageable via a new UI surface | Must-have | ✅ |
| R6 | Silent failure is acceptable | Must-have | ✅ |
| R7 | Browser timezone captured on create/edit; schedule runs in that timezone | Must-have | ✅ |
| R8 | Scheduling uses Solid Queue infrastructure, not a system cron daemon | Must-have | ✅ |
| R9 | App does not depend on Solid Queue's internal AR model schema | Must-have | ✅ |
| R10 | Notifications are out of scope | Out | — |
| R11 | At most one fire per schedule window; missed runs fire once on recovery | Must-have | ✅ |
| R12 | An agent can create a scheduled task programmatically during a conversation via a tool call | Must-have | ✅ |
| R13 | Tasks can be one-shot (fire once at a specified time, then auto-expire) | Must-have | ✅ |
| R14 | One-shot tasks appear in a separate section on the scheduled tasks UI page, with a link to the originating chat | Must-have | ✅ |
| 🟡 R15 | Current datetime injected into LLM context for every conversation | Must-have | ✅ |
