---
shaping: true
---

# Agent Task List — Shaping

## Problem

Agents lose discipline as conversations grow. At the start of a chat, the agent has fresh context — it reads AGENTS.md, follows TDD instructions, plans well. But as tool results and back-and-forth fill the context, the agent drifts and forgets intermediate goals. File-based task tracking didn't work because files are passive — the agent never read them back.

## Solution

A DB-backed checklist per chat, managed by the agent via tools, injected into the system prompt by ConversationRunner so the agent always sees it. Visible read-only in the UI.

## Design

### Naming: ChatStep (not ChatTask)

"Task" is already heavily loaded in this codebase — thread = task = session (D19), Chat has `task_status` with AASM states. The agent's internal work items are called **steps** to avoid confusion. Model: `ChatStep`.

### Model: `ChatStep`

```ruby
# belongs_to :chat
# Fields:
#   title: string (required)
#   status: string (default: "pending") — pending, in_progress, completed
#   position: integer (for ordering)
```

Scoped to a single chat (D19: thread = task = session). Flat list, no nesting. Position determines display order.

**Status is a plain string, no AASM.** Steps are lightweight — they're a cognitive aid, not a workflow engine. Any transition is valid (pending -> completed, completed -> in_progress, etc.). The agent manages them freely.

**Position management:** `CreateSteps` sets position starting from `MAX(position) + 1` on the chat's existing steps (or 1 if none exist). Sequential from there.

### Tools

Two tools, available to all agents. Both receive `chat:` via constructor injection (same pattern as existing tools via `Agent#tools(chat:)`).

**`Daan::Core::CreateSteps`** — Bulk-creates steps. Accepts an ordered list of step titles. Returns the created steps with their positions. If steps already exist on the chat, appends new ones (not idempotent — calling twice creates duplicates, which is fine; the agent can see the list and won't repeat itself).

**`Daan::Core::UpdateStep`** — Updates a step's status. Identified by **position** (integer), not title. Position is stable and unambiguous. Agent sees positions in the system prompt.

**Deliberately out of scope for V1:** delete, reorder. If the agent creates a bad list, it can mark items completed and create new ones. Noted as a future option, not needed now.

### System Prompt Injection

ConversationRunner appends the current step list to the agent's system prompt before every LLM call. The system prompt is a separate API field (not a message), so it's always visible regardless of conversation length or compaction.

Format:

```
[agent's .md system prompt]

## Your Current Steps
1. [x] Clone the repository
2. [in progress] Write tests for the auth module
3. [ ] Implement the auth module
4. [ ] Open a PR
```

Numbers are positions. If no steps exist, nothing is appended.

**One-turn lag:** When the agent calls `CreateSteps`, the steps are created mid-turn. The agent won't see them in the system prompt until the next LLM call. This is fine — the tool response confirms what was created, and from the next turn onward the list is always visible.

### What Survives Compaction

The step list is not in the message stream — it lives on a separate model, injected into the system prompt fresh each LLM call. Compaction (D23) doesn't touch it. This is the key advantage over file-based or message-based approaches.

### Broadcasts

Tools call broadcasts explicitly after mutation (consistent with project convention — no model callbacks for broadcasts). The `ChatStepListComponent` re-renders the full list on any change. Broadcasts to the chat's Turbo stream.

### UI

A `ChatStepListComponent` rendered in the thread view as a read-only checklist. Visible in "messages + tool calls" observability mode (D17). Updated live via Turbo Stream.

## Out of Scope

- Human editing steps from the UI
- Nested/hierarchical steps
- Step dependencies or blocking relationships
- Cross-chat step lists
- Delete or reorder tools (agent can mark completed and create new ones)
