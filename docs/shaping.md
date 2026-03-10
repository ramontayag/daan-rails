---
shaping: true
---

# Daan — Shaping

## Source

> I want to make a fully agentic team of agents.
>
> - self-modifying, with guard-rails. The team is aware of its repository, can pull it down, make changes, and make a pull request. The PR is reviewed and merged by a human, but of course, its own agents may review it. It can create other agents this way if it needs specialization.
> - it's like Swarm (https://github.com/parruda/swarm), but there are some differences. In Swarm, you can't really talk to individual agents, but here, you can. Think of them as an external team on Slack that you can ping the point person who can delegate tasks to the others, or you can ping individual agents.
> - it's learning -- maybe it uses SwarmMemory. For example, when asked to make a change in a new repository, it will find its way to the right agent (let's say developer) and the developer will download and study it. It will then form memories about the repository so that next time it works on it, it can retrieve the memories it has about it and not figure out everything again. These memories may be shared by all agents.
> - There's a daan-core that is the default set of available agents and core capabilities. Maybe this is an engine, or at least a gem. For quick development, it can live in `/vendor` for now.
> - The app will also have a built-in Slack-like chat. It is HTML-first. In the chat interface the human user can see all other agents on the left like individuals in Slack. They can DM the "Chief of Staff" and ask it questions like "I want to make a change on this repo, please get it done" and it may delegate to the eng lead, which will delegate to the devs. Replies are done in a thread, which simulates a session in Claude. The Slack-like app allows the "workspace" to change though -- one can change the view to see how an agent would see it. For example, I can switch to the Chief of Staff (CoS) and I will see a message from me. Then I can go to the engineering manager DM and see that "I" (CoS) made a message to ask them to make a change. I can then switch to the Developer view and see that the eng manager sent me a message to work on a task. I need help thinking through how actual sessions in the AI will work -- maybe every task has its own session, and there's a rolling window of compaction so if there's a lot of back and forth with a single task we won't hit the limit. The agent's status may be seen in Slack like "busy on task abc" just like slack.
> - Agents may have their own workspace. The simplest would just be a directory in the file system. Next would be something like Firejail. Another level up is their own machine (can be docker, or a VM, or a bare metal computer) based on what their work. This is just like how humans operate.

---

## Problem

There's no good way to run a persistent team of AI agents that feels like managing a real team. Existing frameworks (Swarm, CrewAI, etc.) treat agents as pipeline steps or background workers — you can't observe their conversations, switch perspectives, or interact with individuals. There's no sense of "who's doing what right now" and no persistent learning across tasks.

## Outcome

A Rails app where a human manages an AI team through a Slack-like interface. Each agent is an addressable individual with its own perspective, memory, and workspace. The team can self-modify (create new agents, evolve its own code) with human oversight via PRs. Work is observable — you can see any agent's view of any conversation.

---

## Requirements (R)

| ID | Requirement | Status |
|----|-------------|--------|
| R0 | Human can message individual agents and see their responses in a chat UI | Core goal |
| R1 | Agents can delegate tasks to other agents (hierarchical or peer-to-peer) | Core goal |
| R2 | Agent-to-agent messages are observable — human can switch perspective to see any agent's "inbox" | Core goal |
| R3 | Agents have persistent memory (file-based, FAISS + ONNX embeddings, built-in to daan-core) that survives across tasks and sessions — no human approval needed for memories | Must-have |
| R4 | Agents can modify their own repository (clone, branch, commit, PR) with human approval via PR merge | Must-have |
| R5 | A default team ("daan-core") ships with the app and provides base agent roles | Must-have |
| R6 | Each agent has a workspace defined in its agent definition (directory, Docker, VM); V1 implements directory only | Must-have |
| R7 | Chat UI is HTML-first (Hotwire/Turbo Streams, ViewComponents, no SPA framework); full page reload renders normal HTML | Must-have |
| R8 | Each task gets its own LLM session with bounded context; agents are non-blocking and can work on multiple tasks concurrently | Must-have |

---

## Decisions

Resolved during shaping Q&A:

### D1: Session Model
Each agent has its own LLM session per task. When Agent A delegates to Agent B, B gets a separate session. B replies asynchronously — A doesn't block, it continues with other work. Each agent has an inbox and a task queue, like a human on Slack.

### D2: Agentic Loop Limit & Escalation
Each agent has a `max_turns` setting (configurable per agent definition, system default as fallback). This limits how many LLM calls an agent can make within a single task's agentic loop — like Claude CLI's `--max-turns`. When the limit hits, the agent stops, summarizes what it accomplished and what's unresolved, and sends that back to its delegator. The delegator decides: give more guidance, retry, reassign, or escalate up the chain (dev -> eng manager -> CoS -> human). There is no limit on the number of messages between agents — only on an agent's autonomous loop per task execution.

### D3: LLM Provider
Use RubyLLM for multi-provider abstraction. Agent definitions specify which provider/model to use. Higher-level agents (CoS) may use more capable models (Opus), lower-level agents may use simpler/cheaper/local models.

### D4: Architecture — Three Layers
1. **daan-core** (gem) — agent runtime: message routing, task queues, sessions, memory, workspace management + default agent definitions (CoS, eng manager, dev, etc.). Has its own repo, managed by Ramon.
2. **daan-ui** (engine) — Slack-like chat interface, perspective switching, observability. Optional — replaceable with real Slack, Campfire, etc.
3. **daan-rails** (this repo) — reference deployment that mounts both engines. The "demo."

### D5: Self-Modification
Agents can PR changes to both:
- **Deployment repo** (common) — new agent definitions, config changes
- **daan-core repo** (rare) — framework improvements

Target repo is a config in the deployment. Both go through human PR approval. Which repo to target is configured in the Rails app.

### D6: Memory
Built-in to daan-core (not a Swarm dependency). DB-backed: Memory model with content, type (concept/fact/skill/experience), and embedding vector column. Embeddings generated locally via `informers` gem (ONNX). Vector search via `neighbor` gem (sqlite-vec). Four memory types: concepts, facts, skills, experiences. Shared across all agents. No approval needed — memories are internal state. Memory tools: `Daan::Core::WriteMemory`, `Daan::Core::ReadMemory`, `Daan::Core::SearchMemory`.

### D7: Workspace Isolation
Defined per agent in the agent definition file (e.g., `workspace: directory`, `workspace: docker`). Deployments can override daan-core defaults for any agent. V1 implements filesystem directories only; Docker/VM adapters come later.

### D8: Thread Model
1:1 DMs only. No group channels. Group coordination happens through delegation (CoS relays between agents in separate 1:1s). Simpler and maps cleanly to session-per-task model.

### D9: Real-Time UI
Turbo Streams over WebSocket for live updates. ViewComponents render the partials. Progressive enhancement — full page reload renders normal HTML without JS.

### D10: V1 Package Structure
Monolith with clear module boundaries. `lib/daan/core/` for the agent runtime, `lib/daan/chat/` for the UI engine. Same repo, extract into separate gem + engine once interfaces stabilize.

### D11: No Swarm Dependency
Daan does not depend on Swarm or SwarmSDK. Inspired by Swarm's approach (especially SwarmMemory) but builds its own runtime, tools, and memory layer. Avoids pulling in unused orchestration code and keeps the dependency tree clean.

### D12: Task Lifecycle
A task is created when a human sends a message to an agent, or when an agent delegates to another agent (sub-task, linked to parent). Task states: `pending` -> `in_progress` -> `completed` | `failed` | `blocked`. When blocked, the agent reports back to its delegator with a summary. The delegator decides next steps — retry, reassign, or escalate. Tasks are not reassigned; information moves up the chain, not the task itself.

### D13: Agent Definition Format
Frontmatter Markdown files. YAML front-matter for structured config (name, model, max_turns, workspace, delegates_to, tools). Markdown body is the system prompt. Stored in `lib/daan/core/agents/` for defaults, `config/agents/` for deployment overrides. Same-name file in deployment takes precedence (like Rails engine view overrides).

### D14: Tool Interface
Tools are Ruby classes following a daan-core interface. Built-in tools (e.g., `Daan::Core::Read`, `Daan::Core::Write`, `Daan::Core::Bash`, `Daan::Core::DelegateTask`, memory tools) ship with daan-core. Custom tools use full class names (e.g., `MyApp::SecurityAuditTool`). `delegates_to` in agent definitions is a hard constraint — agents cannot message agents not on their list.

### D15: Agents and Tool Scope
Agent tools are scoped to their workspace. A `Daan::Core::Read` call from an agent is restricted to that agent's workspace directory. This is the V1 security boundary — no sandboxing, but filesystem operations are workspace-scoped by the tool implementations.

### D16: Perspective Switching
Read-only. Human can view any agent's perspective but cannot send messages as that agent. Layout stays the same — inputs/send buttons are disabled. URL structure: `/:perspective/chat` where perspective is `me` (human default) or an agent name (e.g., `/chief_of_staff/chat`). Sidebar shows the agent's conversations, unread counts, status. A dropdown picker at the top (like Slack workspace switcher) navigates between perspectives.

### D17: Observability Layers
Three levels of detail when viewing conversations, togglable:
1. **Messages only** (default) — what the agent sent and received, like reading Slack
2. **Messages + tool calls** — also shows memory searches, delegations, file operations
3. **Full trace** — every LLM call, full reasoning, debug mode

### D19: Thread = Task = Session
Each top-level message in a DM starts a new thread. One thread = one task = one LLM session. When an agent delegates, the delegation message becomes a new thread starter in the delegatee's DM. Parent-child task relationships let you trace delegation chains across perspectives.

### D20: Notifications
No separate notification system. Agents communicate results, blockers, and escalations as messages — which show up as unread in the sidebar. Unread badges and bold text on agent names in the sidebar are sufficient. Everything eventually bubbles up to the human as a message from the CoS (or whichever agent the human is working with).

### D21: SQLite for V1
SQLite is fine for V1 (single user, handful of agents). Acknowledge write contention as a scaling boundary. If it becomes a problem, swap to Postgres — Rails makes this straightforward.

### D18: Frontend Stack
Tailwind CSS for styling. ViewComponents for all UI components. Lookbook for component development/preview catalog. This allows developing UI components independently of the agent runtime.

### D22: Execution Model — Job Chain, Not Long-Running Loop
The agentic loop is not one long-running job. It's a chain of small Solid Queue jobs:
1. **LLM Job**: Load thread context, call LLM. If the LLM responds with text → save as message, done. If the LLM responds with tool call(s) → save as message(s), enqueue Tool Job(s).
2. **Tool Job**: Execute the tool. Save the result as a message in the thread. Enqueue a new LLM Job to continue.
3. Repeat until: LLM produces a text-only response, or `max_turns` is hit (turn counter increments per LLM Job).

An agent can kick off multiple tools concurrently (e.g., three downloads) — each is its own Tool Job. As each finishes, it posts a result message which triggers a new LLM Job. The agent is event-driven — it reacts to messages in its thread, whether from tools, other agents, or the human. It is not a running process.

Per-thread concurrency lock: only one LLM Job runs at a time per thread. Tool results arriving while the LLM is processing queue up as messages the agent sees on its next turn. This prevents multiple simultaneous LLM calls from stomping on each other within the same thread.

The human can also send messages into a thread while the agent is working — those are just more messages the agent will see on its next LLM turn.

### D23: Context Compaction
When a thread exceeds the context window threshold, compact it:
1. Summarize old messages into a compact summary message
2. Extract key learnings and write them to memory (concepts, facts, skills, experiences)
3. Subsequent LLM Jobs see: [summary] + [recent messages] + [relevant memories via search]
Memories outlive the thread and are reusable across future tasks.

### D24: PR Feedback Loop
V1: the human tells the agent. If a PR is rejected, the human goes back to the thread and says "PR was rejected because X, try Y." No webhooks or GitHub polling in V1 — the agent doesn't watch GitHub. Same as working with a human contractor. Webhooks can be added later as an optimization.

### D25: Agent Status
Agents show their status in the sidebar: "idle" or "busy on Task #DB-ID". Updated as tasks start and complete.

### D26: Security Model — Tools Are the Gate
Tools are the permission system. The agent definition is the access control list. If an agent has a tool, it can run it. If it needs new capabilities, it creates a new tool or adds an existing one to its definition — both require a PR (human approval). No separate approval gates for individual actions. `max_turns` is the only runtime limit; cost control is implicit via turn limits and model selection.

### D27: Initial Agent Team
V1 ships with three agents in daan-core: Chief of Staff, Engineering Manager, Developer. Additional specialist agents (QA, DevOps, Designer, etc.) can be added by the deployment or by the agents themselves via PR.

### D28: Git Credentials
V1: single GitHub personal access token via env var (`GITHUB_TOKEN`). All agents share it. Git tools use it for clone, push, and PR creation. GitHub App or per-agent tokens can come later.

### D29: Message-Driven Execution ("Heartbeat Rule")
Any new message in a thread where no LLM Job is in flight enqueues an LLM Job for the thread's agent. This is the single rule that drives the entire system. It handles: human sends a message (agent responds), tool completes (agent continues), delegation result arrives (delegator reacts), delegator sends guidance (agent retries). No special-case triggers needed.

### D30: ReportBack Tool (Upward Flow)
`Daan::Core::ReportBack` posts a message in the *parent* task's thread. This is how results flow up the delegation chain: Dev finishes -> EM's LLM Job fires in EM↔Dev thread -> EM reads result -> EM uses `ReportBack` to post in CoS↔EM thread -> CoS's LLM Job fires -> CoS uses `ReportBack` to post in Human↔CoS thread. Each agent in the chain reads, evaluates, and summarizes before reporting up.

### D31: Concurrent Tool Fan-In (Keep It Simple)
No counter or barrier for concurrent Tool Jobs. Every Tool Job completion posts a result message, which triggers an LLM Job (per D29). The per-thread lock means only one LLM Job runs at a time. The first LLM Job sees one tool result; if more arrive during processing, they queue up as messages for the next turn. The agent acts on info as it arrives and adjusts — same as humans. No tracking of pending tool counts.

### D32: Continuing an Existing Sub-Thread
When a delegator wants to send guidance back down to a sub-agent (whether after max_turns, after a blocked report, or after getting clarification from the human), it sends a new message in the **existing** sub-thread — not a new one. Same thread, same context — no information lost. The sub-agent picks up from where it left off with fresh direction.

**V3 limitation:** `DelegateTask` always creates a new sub-chat. If guidance needs to flow back down the chain (e.g., Dev is stuck → EM asks human → human answers → EM tells Dev to continue), the delegating agent must include enough context in a fresh DelegateTask to compensate. Lossy but functional. A "continue existing sub-chat" mechanism (idempotent DelegateTask or a separate ContinueTask tool) is deferred to a later slice.

### D33: Task States Clarified
- `pending` — created, waiting to be picked up
- `in_progress` — agent is actively working (LLM/Tool Jobs in flight)
- `completed` — agent produced a final response, work is done
- `blocked` — agent hit max_turns or an obstacle it can't resolve. Reports back to delegator.
- `failed` — unrecoverable error (LLM API down, unhandled exception). No automatic recovery. Human or delegator must retry.

Parent task state is managed by the parent agent, not automatically. When a child task completes, the parent agent's LLM Job processes the result (via D29/D30) and decides whether its own task is also complete.

### D34: Message Metadata & Token Tracking
Message has a `metadata` JSON column storing all available data: token_count, input_tokens, output_tokens, cost_usd, response_time_ms, model, tool_name, tool_duration_ms, turn_number, memory_ids (which memories were injected), compacted (boolean). Save everything — can trim later. Context compaction (D23) triggers at start of LLM Job when sum of message token counts exceeds 80% of the model's context window. Compaction LLM call does not count against max_turns.

### D35: Human Identity
V1: single human user, no User model. Messages from the human have `sender_type: "human"`. The human is an implicit participant in threads. Multi-user support is a future concern.

### D36: Agent Loader Reloading
Development: agent definition files re-read on each request. A dev-only command (rake task or UI button) pulls the latest changes from a branch and hot-reloads agent definitions + tool classes. This lets you test the real self-modification flow (agent PRs to GitHub) with a fast feedback loop — pull + reload instead of merge + deploy. Production: loaded once at boot, reloaded on deploy/restart.

### D39: Chatty Agent Prevention
System prompts instruct agents: after using `ReportBack`, your work in this thread is done — do not continue the conversation. Leaf agents (Developer) do not wait for acknowledgment after reporting results. If this proves insufficient, a system-level rule can be added: `ReportBack` ends the agentic loop for that thread.

### D37: Known V1 Limitations
- No task cancellation. Human sends "stop" in thread; agent sees it on next LLM turn. No hard kill.
- No memory provenance tracking (no `created_by` or `source` on Memory records).
- No memory conflict resolution (contradictory memories may coexist).
- SQLite write contention under heavy concurrent load (D21).

### D38: Initial Delegation Graph
CoS delegates_to: [engineering_manager]. Engineering Manager delegates_to: [developer]. Developer delegates_to: [] (leaf agent).

---

## Shape A: Event-Driven Agent Team

| Part | Mechanism |
|------|-----------|
| **A1** | **Core data model** — Agent — plain Ruby value object (`Daan::Agent`), in-memory only, loaded from definition files into `Daan::AgentRegistry`. No agents table. Agent status (idle/busy) derived from Chat.task_status — not stored. Thread/Chat (agent_name:string, task_status, turn_count, per-thread LLM lock via Solid Queue concurrency controls), Message (chat, role [user/assistant/tool], content, message_type [text/tool_call/tool_result/summary], metadata JSON with token_count), Memory (content, type [concept/fact/skill/experience], embedding vector via neighbor gem). Task state lives on Chat (D19: thread = task = session). |
| **A2** | **Agent loader** — Reads frontmatter markdown files from `lib/daan/core/agents/` and `config/agents/` (overrides). Parses YAML front-matter into agent config. Registers `Daan::Agent` objects into `Daan::AgentRegistry` (in-memory) at boot (production) or per-request (development). Deployment overrides take precedence (same-name file). No DB writes. |
| **A3** | **Job chain execution** — Heartbeat rule (D29): any new message in an idle thread enqueues an LLM Job. LLM Job: load thread context (summary + recent messages + relevant memories via vector search on last message), call RubyLLM, save response as Message with token metadata. If tool call(s) → enqueue Tool Job(s). Tool Job: execute tool, save result as Message, post triggers new LLM Job (D29). Per-thread lock via Solid Queue concurrency_key. Turn counter on Task increments per LLM Job, enforces max_turns. Compaction check at LLM Job start (D23/D34). |
| **A4** | **Tool system** — Base class `Daan::Core::Tool` with description + call interface. Built-in: `Read`, `Write`, `Bash`, `DelegateTask`, `ReportBack`, `WriteMemory`, `SearchMemory`. All filesystem tools scoped to agent's workspace directory. Git tools (A9) allowed network/API access. Custom tools use full Ruby class names. `delegates_to` enforced by `DelegateTask`. |
| **A5** | **Delegation & return path** — `DelegateTask` creates a sub-task (linked to parent), a new Thread between delegator and delegatee, and a first Message. Heartbeat rule (D29) triggers delegatee's LLM Job. `ReportBack` (D30) posts results in the parent task's thread, triggering the delegator's LLM Job. Each agent reads, evaluates, and summarizes before reporting up. |
| **A6** | **Memory system** — `informers` gem for local ONNX embeddings, `neighbor` gem with sqlite-vec for vector search. Memory model in DB with content, type, embedding. `SearchMemory` tool for explicit search. Automatic retrieval: each LLM Job searches memories using the last message as query, injects top results into context. Also used during compaction: extract learnings before summarizing old messages. |
| **A7** | **Chat UI** — Slack-like layout: sidebar with agent list (name, status, unread count), main area with threaded DMs. ViewComponents for all UI elements. Turbo Streams over WebSocket for live message updates (per-thread subscriptions). Tailwind for styling. Lookbook for component catalog. |
| **A8** | **Perspective switching** — Routes: `/:perspective/chat`. Dropdown picker at top. Same layout/components, loads different agent's data. Sidebar filtered to show the perspective agent's conversation partners. Inputs disabled in non-self views. Observability toggle: messages only → + tool calls → full trace. Message alignment flips based on perspective (sender's messages right-aligned). |
| **A9** | **Self-modification** — Git tools: `GitClone`, `GitCommit`, `GitPush`, `CreatePR`. Git tools have network/API access (exempt from workspace filesystem scoping). Target repo configured per deployment. GitHub auth via `GITHUB_TOKEN` env var. Agent creates branch in workspace, makes changes, opens PR. Changes take effect on next deploy (D36). |

All flags resolved. Ready to slice.
