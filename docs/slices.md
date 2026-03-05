---
shaping: true
---

# Daan — Slices

Vertical slices of Shape A (Event-Driven Agent Team). Each slice ends in demo-able UI.

---

## Slice Overview

| Slice | Title | Parts | Demo |
|-------|-------|-------|------|
| **V1** | Human chats with one agent | A1 (subset), A2 (subset), A3 (subset), A7 (subset) | Human sends message to CoS, sees LLM response stream in |
| **V2** | Agent uses tools | A3 (tool jobs), A4 | Ask agent to read a file, see tool calls and results in thread |
| **V3** | Delegation chain | A1 (task parent-child), A4 (DelegateTask, ReportBack), A5 | Message CoS, watch it delegate down to Dev and results flow back up |
| **V4** | Perspective switching | A8 | Switch to EM view, see its conversations from its perspective |
| **V5** | Memory | A1 (Memory model), A6 | Agent remembers context from a prior task, uses it in a new one |
| **V6** | Self-modification | A4 (git tools), A9 | Agent creates a branch, commits changes, opens a PR |
| **V7** | Context compaction | A3 (compaction) | Long conversation stays coherent after compaction |

---

## V1: Human Chats With One Agent

The thinnest possible end-to-end slice. A human sends a message to the Chief of Staff and gets an LLM response in a Slack-like chat UI. No tools, no delegation, no memory — just conversation.

### What We Build

| Part | Mechanism | From |
|------|-----------|------|
| **V1.1** | **Data model (subset)** — Agent (name, status), Thread (two participants, per-thread concurrency lock key), Message (thread, sender, sender_type [human/agent], content, message_type [text], metadata JSON), Task (state [pending/in_progress/completed/failed], assigned_agent, turn_count, max_turns) | A1 |
| **V1.2** | **Agent loader (single agent)** — Read `lib/daan/core/agents/chief_of_staff.md`, parse YAML frontmatter (name, model, max_turns). Create/sync Agent DB record on boot. No deployment overrides yet. | A2 |
| **V1.3** | **LLM Job (text-only loop)** — Heartbeat rule: new message in idle thread enqueues LLM Job via Solid Queue. LLM Job loads thread messages, calls RubyLLM with agent's model and system prompt, saves response as Message with token metadata. Text-only response marks task completed. Turn counter increments per LLM Job, enforces max_turns (task goes to blocked state). Per-thread concurrency via Solid Queue concurrency_key. | A3 |
| **V1.4** | **Chat UI (minimal)** — Sidebar: list of agents (just CoS) with name and status. Main area: message thread for the selected DM. Input box at bottom to compose and send. Messages right-aligned for human, left-aligned for agent. Turbo Streams over WebSocket for live message delivery. Full page reload renders normal HTML. ViewComponents for message bubble, sidebar agent item, compose bar. Lookbook previews for all component states. Tailwind CSS. | A7 |

### Affordances

**UI Affordances**

| # | Place | Affordance | Type | Wires Out |
|---|-------|-----------|------|-----------|
| U1 | Sidebar | Agent list item (CoS) | Display | Shows name, status dot (idle/busy) |
| U2 | Sidebar | Unread indicator | Display | Bold name + count when unread messages exist |
| U3 | Thread view | Message bubble | Display | Shows sender, content, timestamp; right-aligned for human, left for agent |
| U4 | Thread view | "Agent is thinking..." indicator | Display | Shown while LLM Job is in flight |
| U5 | Compose bar | Text input | Field | — |
| U6 | Compose bar | Send button | Action | Creates Message (human), creates Task (pending), triggers heartbeat |

**Non-UI Affordances**

| # | Affordance | Type | Wires Out |
|---|-----------|------|-----------|
| N1 | Agent loader | Service | Reads definition file, syncs Agent record |
| N2 | Heartbeat check | Callback | On Message create: if thread idle (no in-flight LLM Job), enqueue LlmJob |
| N3 | LlmJob | Job | Load messages, call RubyLLM, save response Message, update Task turn_count. If max_turns hit → task.blocked! |
| N4 | Thread concurrency lock | Solid Queue concurrency_key | One LLM Job per thread at a time |
| N5 | Task state machine | Model concern | pending → in_progress → completed/failed/blocked |
| N6 | Agent status updater | Callback | Task in_progress → agent busy. Task completed/blocked/failed → agent idle. |
| N7 | Turbo broadcast | After Message create | Broadcasts message to thread's Turbo Stream channel |

### Wiring

```
Human types message (U5) → Send (U6)
  → Creates Message(sender_type: human) + Task(pending)
  → N7 broadcasts message to thread stream → U3 renders bubble
  → N2 heartbeat fires → enqueues N3 (LlmJob)
  → N5 transitions task: pending → in_progress
  → N6 updates agent status → U1 shows "busy"
  → U4 shows thinking indicator

N3 (LlmJob) runs:
  → Loads thread messages
  → Calls RubyLLM (agent model + system prompt + messages)
  → Saves response as Message(sender_type: agent)
  → N7 broadcasts → U3 renders agent bubble, U4 hides
  → Increments turn_count
  → If text response: N5 task → completed, N6 agent → idle
  → If max_turns hit: N5 task → blocked, N6 agent → idle
```

### What We Defer

- Tools and tool jobs (V2)
- Delegation, sub-tasks, ReportBack (V3)
- Perspective switching (V4)
- Memory and embeddings (V5)
- Git/self-modification (V6)
- Context compaction (V7)
- Multiple agents (V3 loads all three)
- Observability toggle (V4)
- Deployment config overrides for agent loader (V3)

### Demo Script

1. Boot the app. Sidebar shows "Chief of Staff" with green idle dot.
2. Click on CoS. Empty thread view with compose bar.
3. Type "Hello, what can you help me with?" and send.
4. Message appears right-aligned. "Thinking..." indicator shows.
5. CoS responds with a message about its capabilities. Left-aligned bubble.
6. Status returns to idle.
