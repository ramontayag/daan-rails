---
shaping: true
---

# V2: Agent Uses Tools — Slice Detail

The job chain extends beyond a single LLM call. When the LLM returns tool calls, Tool Jobs execute them and post results back, triggering the next LLM Job. Human sees tool calls and results as collapsible blocks in the thread, with a "Typing..." indicator while any job is in flight.

---

## What We Build

| Part | Mechanism | From |
|------|-----------|------|
| **V2.1** | **Tool base** — `Daan::Core::Tool` abstract class with `.description` and `.call(params, workspace:)` interface. Agent frontmatter declares `tools:` list (class names). LlmJob loads tool definitions from the agent's tools list and passes them to RubyLLM. | A4 |
| **V2.2** | **Read + Write tools** — `Daan::Core::Read` reads a file; `Daan::Core::Write` writes content to a path. Both validate that the given path does not escape the provided `workspace:` directory (no path traversal). The workspace location is whatever the agent definition specifies — the tools make no assumptions about where workspaces live. For V2, Developer's workspace is `tmp/workspaces/developer/`, created at first use. | A4 |
| **V2.3** | **Developer agent** — New `lib/daan/core/agents/developer.md` with model, system prompt, `max_turns`, `workspace: directory`, `tools: [Daan::Core::Read, Daan::Core::Write]`. Loaded at boot alongside CoS. Appears in sidebar. Directly chattable. | A2 + A4 |
| **V2.4** | **Tool job chain** — LlmJob: if RubyLLM response contains tool call(s), save each as a `tool_call` Message, enqueue a `ToolJob` per call. ToolJob: instantiate tool, execute with params + workspace path, save result as `tool_result` Message in the same chat. Heartbeat rule (D29) fires on that message → new LlmJob. Per-thread concurrency lock still applies. | A3 |
| **V2.5** | **Tool message types** — Add `message_type` string column to Message (default: "text"; values: "tool_call", "tool_result"). Tool call message stores `{tool_name, params}` JSON in `content`. Tool result message stores output string in `content`. `metadata` on tool_result stores `tool_duration_ms`. | A1 |
| **V2.6** | **Tool block UI + Typing indicator** — `ToolCallComponent`: collapsible block showing tool name + params. Starts in "running..." state when tool_call message is broadcast. Updates in place (Turbo Stream replace) to show result once tool_result message is saved — call and result in one block, expandable. "Typing..." indicator: a broadcast target in the thread view, shown when `task_status → in_progress`, cleared when `completed`/`failed`/`blocked`. Lookbook previews: running, collapsed-with-result, expanded-with-result, typing indicator. | A7 |

---

## Affordances

### UI Affordances

| # | Place | Affordance | Type | Wires Out |
|---|-------|-----------|------|-----------|
| U1 | Sidebar | Developer agent list item | Display | Shows name, status dot (idle/busy) |
| U2 | Thread view | "Typing..." indicator | Display | Shown while LlmJob or ToolJob is in flight; cleared on completion |
| U3 | Thread view | Tool call block (running) | Display | Shows tool name + params; spinner while ToolJob executes |
| U4 | Thread view | Tool call block (done) | Display | Updates in place: shows tool name + params + result; collapsible |
| U5 | Thread view | Message bubble | Display | Agent's final text response (same as V1) |
| U6 | Compose bar | Text input + Send | Action | Creates Message (human), triggers heartbeat |

### Non-UI Affordances

| # | Affordance | Type | Wires Out |
|---|-----------|------|-----------|
| N1 | Developer agent loader | Service | Reads developer.md, registers `Daan::Agent` into registry |
| N2 | Workspace directory setup | `Daan::Core::Tool` base | Ensures workspace directory exists before first tool call |
| N3 | `Daan::Core::Read` | Tool | Reads file at path; validates within provided workspace |
| N4 | `Daan::Core::Write` | Tool | Writes content to path; validates within provided workspace |
| N5 | `ToolJob` | Job | Executes tool, saves tool_result Message, heartbeat fires → new LlmJob |
| N6 | Tool call broadcast | in LlmJob | On tool_call Message save: broadcasts `ToolCallComponent` (running state) to thread |
| N7 | Tool result broadcast | in ToolJob | On tool_result Message save: Turbo Stream replace → updates `ToolCallComponent` in place with result |
| N8 | Typing indicator broadcast | in LlmJob + ToolJob | Broadcast "Typing..." on `in_progress`; broadcast clear on `completed`/`failed`/`blocked` |

---

## Wiring

```
Human types message (U6) → Controller creates Message(role: user)
  → Broadcast user bubble → thread
  → Heartbeat → enqueues LlmJob

LlmJob runs:
  → chat.start! → in_progress
  → N8: broadcast "Typing..." (U2)
  → N1: broadcast AgentItemComponent → sidebar busy dot
  → Load messages + tool definitions from agent
  → Call RubyLLM

  If text-only response:
    → Save Message(role: assistant, message_type: text)
    → Broadcast message bubble → thread (U5)
    → chat.complete!
    → N8: broadcast clear Typing indicator
    → N1: broadcast AgentItemComponent → sidebar idle dot

  If tool call(s) in response:
    → For each tool call:
      → Save Message(role: assistant, message_type: tool_call)
      → N6: broadcast ToolCallComponent (running state) → thread (U3)
      → Enqueue ToolJob

ToolJob runs:
  → Instantiate tool (Read or Write)
  → Execute with params + workspace path
  → Save Message(role: tool, message_type: tool_result, content: output)
  → N7: Turbo Stream replace → ToolCallComponent updates in place (U4)
  → Heartbeat fires on tool_result Message → enqueues new LlmJob

New LlmJob runs (loop continues until text-only response):
  → Context includes all messages including tool results
  → Eventually produces text-only final response → same flow as above
```

---

## What We Defer

- `Bash` tool and any further tools (V3+)
- `DelegateTask`, `ReportBack` (V3)
- Memory tools (V5)
- Cross-workspace access demonstrated in practice (architecture supports it)
- Observability levels toggle (V4)
- Multiple concurrent tool fan-in (D31 — architecture allows it, not demoed)

---

## Demo Script

1. Boot app. Sidebar shows CoS and Developer, both idle.
2. Click Developer. Empty thread.
3. Type: "Create a file called hello.txt with the content 'Hello, world!'"
4. "Typing..." appears. Developer responds: Write tool call block appears (collapsed, "running...").
5. Tool executes. Block updates in place — shows "Write: hello.txt → done" (expandable for full output).
6. Developer sends text: "Done — created hello.txt in my workspace."
7. Type: "Now read it back to me."
8. Read tool call block appears, updates with content. Developer confirms with text showing the content.
