---
shaping: true
---

# Ryan Singer Shaping Agent — Shaping

## Source

> How about ripple checks? I find that very useful -- I've seen the agent be reminded to check for ripple effects. How would we do that in Daan?
> ...
> Hmm.. RubyLLM puts all system messages at the top, so the agent might not pay attention to it. What do you think about an invisible user message?
> Can you make a shaping doc for this?

---

## Problem

Shaping features with an LLM requires a disciplined methodology (R/S notation, fit checks, ripple checks) that gets lost when using a generic agent. The user has to re-explain the process every time, and there's no mechanism to remind the agent to propagate changes across the shaping doc hierarchy (shaping → slices → slice plans).

## Outcome

A dedicated RyanSinger agent in Daan that guides the user through the Shape Up methodology, persists shaping state across sessions, produces structured shaping documents, and automatically reminds itself to check for ripple effects after document updates.

---

## Requirements (R)

| ID | Requirement | Status |
|----|-------------|--------|
| R0 | A named agent embodies the RJS shaping methodology | Core goal |
| R1 | Agent can create and update shaping documents (markdown + Mermaid) | Must-have |
| R2 | After updating a shaping document, agent is reminded to check ripple effects | Must-have |
| R3 | Ripple check reminder is invisible to the human in the UI | Must-have |
| R4 | Agent persists R set, shapes, and decisions across sessions via memory | Must-have |
| R5 | No workspace needed — agent works conversationally | Must-have |

---

## A: RyanSinger agent with injected ripple check

### Agent file

New file: `lib/daan/core/agents/ryan_singer.md`

| Part | Mechanism |
|------|-----------|
| A1 | Agent definition with `name: ryan_singer`, `display_name: Ryan Singer`, Sonnet model, no workspace |
| A2 | Tools: `ReportBack`, `CreateDocument`, `UpdateDocument`, `MemoryWrite`, `MemoryRead`, `MemoryGlob`, `MemoryGrep` |
| A3 | System prompt embeds condensed shaping methodology (R/S notation, fit checks, chunking policy, ripple check awareness) — sourced from `~/.claude/skills/shaping/SKILL.md` |
| A4 | Memory used to persist current R set, selected shape, open decisions across sessions |

### Ripple check

| Part | Mechanism |
|------|-----------|
| A5 | `UpdateDocument` tool detects shaping documents (by `doc_type` or title convention) and calls `Daan::CreateMessage.call(chat, role: "user", content: "[System] Ripple check: ...", visible: false)` after saving |
| A6 | Message appears in LLM context immediately after the tool result — high attention, recency-aware |
| A7 | `visible: false` keeps it hidden from the thread panel UI (existing infrastructure, no migration needed) |

---

## Fit Check

| Req | Requirement | Status | A |
|-----|-------------|--------|---|
| R0 | A named agent embodies the RJS shaping methodology | Core goal | ✅ |
| R1 | Agent can create and update shaping documents | Must-have | ✅ |
| R2 | After updating a shaping document, agent is reminded to check ripple effects | Must-have | ✅ |
| R3 | Ripple check reminder is invisible to the human in the UI | Must-have | ✅ |
| R4 | Agent persists R set, shapes, and decisions across sessions via memory | Must-have | ✅ |
| R5 | No workspace needed — agent works conversationally | Must-have | ✅ |

---

## Open Questions

- **How to detect shaping documents in `UpdateDocument`?** Options: (a) explicit `doc_type` field on Document, (b) title convention (`*Shaping*`, `*— Shaping`), (c) agent always tags documents at creation. Needs a spike.
- **How much of the methodology to embed?** The full `SKILL.md` is ~2000 words. A condensed version risks losing nuance; the full version costs tokens on every turn.
