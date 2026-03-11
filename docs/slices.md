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

## V5: Memory

See [docs/plans/V5-plan.md](plans/V5-plan.md) for full slice detail (parts, tasks, demo script).

---

## V4: Perspective Switching

See [docs/plans/V4-plan.md](plans/V4-plan.md) for full slice detail (parts, tasks, demo script).

---

## V3: Delegation Chain

See [docs/plans/V3-plan.md](plans/V3-plan.md) for full slice detail (parts, tasks, demo script).

---

## V2: Agent Uses Tools

See [docs/plans/V2-plan.md](plans/V2-plan.md) for full slice detail (parts, affordances, wiring, demo script).

---

## V1: Human Chats With One Agent

See [docs/plans/V1-slice.md](plans/V1-slice.md) for full slice detail (parts, affordances, wiring, demo script).

---

## V2 Code Review Findings

Findings from post-implementation review (kieran-rails-reviewer, security-sentinel, code-simplicity-reviewer).

### 🔴 P1 — Critical

| # | Finding | File |
|---|---------|------|
| 1 | **`Object.const_get` on YAML strings** — no allowlist; anyone who can write an agent `.md` file can resolve any constant in the Ruby object space | `agent_loader.rb:9` |
| 2 | **Symlink bypass in `Workspace#resolve`** — `expand_path` is lexical; LLM can Write a symlink inside workspace and Read follows it outside the boundary. Fix: `File.realpath`. Also add null-byte guard. | `workspace.rb:12-17` |
| 3 | **N+1 query in `ToolCallComponent#result`** — one `Message.find_by` per tool call; pre-load result messages in `broadcast_new_messages` and pass `result:` explicitly | `tool_call_component.rb:14` |
| 4 | **Silent `return unless chat.may_start?`** — violates CLAUDE.md "let it crash"; raise or let AASM raise | `conversation_runner.rb:5` |
| 5 | **Silent `rescue AASM::InvalidTransition` in `run_llm`** — unreachable state, swallows errors, violates "let it crash" | `conversation_runner.rb:32-35` |

### 🟡 P2 — Important

| # | Finding | File |
|---|---------|------|
| 6 | **XSS** — tool results and message bodies rendered without explicit `h()`; `ruby_llm` could mark content `html_safe` bypassing auto-escape | `tool_call_component.html.erb:9`, `message_component.html.erb:6` |
| 7 | **Broadcast race** — `broadcast_append` (running...) then `broadcast_replace` (result); if client hasn't applied the append when replace arrives, Turbo silently drops the completed tool call | `conversation_runner.rb:64-91` |
| 8 | **Assistant text alongside tool calls dropped** in `broadcast_new_messages` but shown in view — inconsistency | `conversation_runner.rb:85-100` |
| 9 | **`TypingIndicatorComponent` owns `id="typing_indicator"`** — fragile coupling between component and view | |
| 10 | **Dead code:** `Workspace#mkdir_p` (never called), `Chat#max_turns_reached?` (runner bypasses it), `Workspace#to_str` (never triggered implicitly) | Multiple |

### 🔵 P3 — Nice to Have

| # | Finding |
|---|---------|
| 11 | CSP initializer entirely commented out — no second layer of XSS defense |
| 12 | `result:` param on `ToolCallComponent` — no caller passes it; fixing #3 resolves this automatically (keep the param, start passing it) |
