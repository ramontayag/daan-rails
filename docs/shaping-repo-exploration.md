---
shaping: true
---

# Repo Exploration — Shaping

## Problem

When a Daan agent clones a new repo, it reads `CLAUDE.md`, `AGENTS.md`, and `README.md` (step 3 of the developer workflow). But many repos now have `.claude/` directories containing skills, and other convention directories (`.opencode/`, `.codex/`, `docs/`, etc.) with useful documentation. Today, Daan agents ignore these entirely. A human developer would browse those files, internalize the relevant ones, and apply them when doing matching work. Daan agents should do the same.

## Outcome

When a Daan agent works in a repo, it leverages the repo's documentation and skills the same way a human would — studying the repo on first encounter, persisting what it found in memory, and loading relevant docs/skills as needed for each task.

## Requirements (R)

| ID | Requirement | Status |
|----|-------------|--------|
| R0 | Agent discovers what documentation and skill directories a repo contains on first encounter | Core goal |
| R1 | Agent re-reads relevant docs/skills from the repo when working in it (always fresh) | Must-have |
| R2 | Works with any convention directory, not hardcoded to specific ones | Must-have |
| R3 | Existing memory search surfaces repo knowledge automatically — no new injection mechanism needed | Must-have |
| R4 | Discovery and loading don't consume excessive context or slow down normal tasks | Must-have |
| R5 | A "study repo" tool packages the scan into one reliable call | Out (add later if agents don't comply with instructions) |
| R6 | Agent instructions guide when to study, when to load memories, when to refresh | Must-have |

### Design notes

- **R2**: Hardcoding `.claude/`, `.opencode/`, `.codex/` means every new convention requires a code change. The agent should look at what's in the repo broadly, not just known directories.
- **R3**: `BuildSystemPrompt` already does a semantic memory search and appends the top 5 results. If the agent writes a well-titled memory for a repo, it gets surfaced when the repo is mentioned in future tasks. No new mechanism needed.
- **R5**: Start with instructions. If agents don't comply reliably, add a dedicated tool that packages the scan into one call.

## Shape A: Instructions + memory + existing search

Selected shape.

| Part | Mechanism |
|------|-----------|
| **A1** | Agent instructions updated: "When you first work in a repo, study it — ls the root, read the README, check for convention dirs (.claude/, .opencode/, .codex/, docs/, etc.), note key files (CONTRIBUTING.md, AGENTS.md, CLAUDE.md, etc.)" |
| **A2** | Agent instructions updated: "Write a memory summarizing what you found — doc locations, available skills/conventions, key files. Title it clearly with the repo name." |
| **A3** | Agent instructions updated: "Before starting work in a repo, check if you have a memory for it. If you do, read the specific docs/skills relevant to your current task." |
| **A4** | Agent instructions updated: "If something seems off or the memory is old, re-study and update it." |
| **A5** | Existing `BuildSystemPrompt` memory search surfaces repo memories when the repo is mentioned in the conversation. No new injection mechanism. |

## Fit Check: R × A

| Req | Requirement | Status | A |
|-----|-------------|--------|---|
| R0 | Agent discovers docs/skills on first encounter | Core goal | ✅ |
| R1 | Agent re-reads relevant docs/skills each time (always fresh) | Must-have | ✅ |
| R2 | Works with any convention directory, not hardcoded | Must-have | ✅ |
| R3 | Existing memory search surfaces repo knowledge automatically | Must-have | ✅ |
| R4 | Discovery and loading don't consume excessive context | Must-have | ✅ |
| R6 | Agent instructions guide when to study, load, refresh | Must-have | ✅ |

## Risks

- **Agent compliance**: The entire shape relies on agents following instructions. Mitigated by: instructions are in the system prompt (seen every LLM call), the existing workflow already has 10 steps agents follow reliably, and R5 is the fallback if this doesn't work.
- **Memory title consistency**: If the agent titles memories inconsistently, semantic search might not surface them. Instructions should specify a naming pattern (e.g., "repo: <owner/repo-name>").
- **Over-reading**: Agent might read too many docs upfront. Instructions should emphasize studying the structure first, reading specific files only when relevant to the current task.
