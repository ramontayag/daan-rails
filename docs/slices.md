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

## V2: Agent Uses Tools

See [docs/plans/V2-plan.md](plans/V2-plan.md) for full slice detail (parts, affordances, wiring, demo script).

---

## V1: Human Chats With One Agent

See [docs/plans/V1-slice.md](plans/V1-slice.md) for full slice detail (parts, affordances, wiring, demo script).
