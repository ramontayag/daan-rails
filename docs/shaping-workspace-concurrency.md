---
shaping: true
---

# Workspace Concurrency — Shaping

## Problem

Multiple concurrent chats can target the same agent (and therefore the same workspace). Without protection, chats conflict — one checks out a different branch while another is mid-edit, or two chats write to the same files. Today this isn't a problem because the system operator manually avoids concurrent tasks, but opening the system to multiple users makes conflicts inevitable.

Agents, unlike humans, don't naturally orient themselves and tend to ignore soft warnings. When they get into a bad workspace state, they spiral rather than recover.

## Requirements (R)

| ID | Requirement | Status |
|----|-------------|--------|
| R0 | Only one chat actively uses an agent's workspace at a time | Core goal |
| R1 | When a chat re-awakens and another chat used the workspace in between, the agent is forced to re-orient before proceeding | Must-have |
| R2 | Re-orientation is automatic — injected as invisible system message before the LLM call, not a tool gate the agent must choose to use | Must-have |
| R3 | Works with multiple users submitting chats to the same agent concurrently | Must-have |
| R4 | Queued chats are visible to users ("Developer is working on another task, yours is queued") | Must-have |
| R5 | Minimal overhead for the common case (single chat, no interleaving) | Must-have |

### Design notes

- **R0**: Solves concurrent access. One chat holds the workspace lock. Other chats queue up. Like a human — you don't work two tasks simultaneously in the same checkout.
- **R1**: Solves stale state. When Chat 33 re-awakens and the lock was held by Chat 44 in between, the agent sees what changed before it even thinks.
- **R2**: Automatic injection is stronger than a tool gate. The agent can't skip it — the workspace state is already in the conversation before the LLM call happens. Same pattern as `warn_approaching_step_limit` — invisible user message with `Daan::SystemTag::PREFIX`.
- **R3**: Key driver. A single operator can self-coordinate. Multiple users can't.
- **R4**: UX requirement. Users need to know why their chat hasn't started yet.
- **R5**: If no other chat ran in between, the lock acquisition is a quick DB check that returns "same holder" — no injection needed.

## Shape A: Workspace lock with automatic re-orientation

Selected shape.

| Part | Mechanism |
|------|-----------|
| **A1** | Workspace lock model — tracks current holder (chat_id), agent_name, previous holder, acquired_at. No job_id — stale detection uses chat status + Solid Queue job existence. |
| **A2** | Lock acquisition in `ConversationRunner` — before running a step, chat acquires the lock. If another chat holds it, the job re-enqueues with a delay (back-off). |
| **A3** | Lock release — chat releases the lock when conversation finishes (completed/blocked/failed). |
| **A4** | Stale lock detection — lock is stale if: (a) holder chat is not `in_progress`, or (b) holder chat is `in_progress` but no unfinished `LlmJob` exists for it in Solid Queue. Uses GlobalID to match chat in serialized job arguments. |
| **A5** | Re-orientation injection — when a chat acquires the lock and the previous holder was a different chat, `ConversationRunner` automatically runs git status/branch/log, injects results as invisible `[SYSTEM]` user message before the LLM call. |
| **A6** | Queue visibility — broadcast to UI when a chat is waiting for the workspace lock. |

### Key flow

```
Chat 33 starts → acquires workspace lock → runs steps → finishes → releases lock
Chat 44 starts → acquires lock (previous: Chat 33) → runs → finishes → releases
Chat 33 re-awakens → acquires lock (previous: Chat 44, not self)
  → ConversationRunner runs git status, branch, log
  → injects invisible message: "Workspace was used by Chat 44 since your last run.
    Branch: feature-x (was: main). Modified: app/models/user.rb, config/routes.rb"
  → LLM call proceeds with full context
  → agent sees the state change and reasons accordingly

Crash scenario:
Chat 44 acquires lock → process killed mid-step → lock stuck
Chat 33 tries to acquire → lock held by Chat 44
  → checks: is Chat 44 still in_progress? Yes.
  → checks: does an unfinished LlmJob for Chat 44 exist? (via GlobalID in arguments)
  → no job found → lock is stale → steals it → proceeds with re-orientation
```

### Resolved questions

- **A6 (agent concurrency key) vs A2 (lock model)**: A6 dropped. The lock model handles both serialization and history. A6 only prevented simultaneous execution but couldn't prevent interleaving between steps. The lock persists across steps within a conversation.
- **Lock timeout / crash recovery**: No arbitrary TTL, no job_id on lock. Stale = holder chat not `in_progress` OR `in_progress` with no unfinished `LlmJob` in Solid Queue. Uses GlobalID match on serialized arguments. Handles: between-step re-enqueue (new job exists), process crash (Solid Queue prunes → retries or exhausts), missed release (chat status changed).
- **Sub-agent chats**: Not a concern. Sub-chats delegate to a *different* agent with a different workspace. No lock sharing needed.

## Fit Check: R × A

| Req | Requirement | Status | A |
|-----|-------------|--------|---|
| R0 | Only one chat actively uses workspace at a time | Core goal | ✅ |
| R1 | Re-awakened chat forced to re-orient if workspace was used by another | Must-have | ✅ |
| R2 | Re-orientation is automatic, not agent-initiated | Must-have | ✅ |
| R3 | Works with multiple users and concurrent chats | Must-have | ✅ |
| R4 | Queued chats visible to users | Must-have | ✅ |
| R5 | Minimal overhead for common case | Must-have | ✅ |

All pass.

## Slices

| Slice | Parts | Demo |
|-------|-------|------|
| **V1** | A1, A2, A3 — Lock model, acquisition with back-off, release | Start two chats with same agent. Second waits until first finishes. Visible in logs. |
| **V2** | A6 — Queue visibility broadcast | User submits chat while agent is busy → sees "Developer is working on another task, yours is queued." Clears when chat starts. |
| **V3** | A5 — Re-orientation injection | Chat 33 finishes. Chat 44 runs, changes branch. Chat 33 re-awakens → invisible system message shows branch change, modified files. Agent responds with awareness. |
| **V4** | A4 — Stale lock recovery | Simulate crashed chat (lock held, no job). New chat detects stale lock, steals it, proceeds. |

### Dependencies

```
V1 ← V2 (needs lock to know when chat is queued)
V1 ← V3 (needs lock history to detect workspace handoff)
V1 ← V4 (needs lock to detect staleness)
V2, V3, V4 are independent of each other
```

Suggested order: V1 → V2 → V3 → V4. V2 is the most user-visible after V1. V4 is an edge case (crashes).

## Archived: Background Tool Execution

We explored backgrounding all tool execution as jobs. Conclusion: not worth the complexity.

- Within a single chat, sequential tool calls (the common case) are functionally identical whether backgrounded or not.
- Cross-chat concurrency already works — separate `LlmJob`s with separate concurrency keys.
- Backgrounding doesn't free workers — the job running the tool is still tied up for the duration.
- The real problem isn't blocking, it's **workspace conflicts between concurrent chats**. That's what this doc now addresses.
