---
shaping: true
---

# Agent Hooks — Slices

Based on [shaping-hooks.md](shaping-hooks.md), selected shape A.

---

## Slice 1: Agent hooks + before_llm_call + Daan::Core::Shaping

**Demo:** Chat with RyanSinger and call `update_document`. The next LLM turn has a `visible: false` ripple check message in the conversation history.

| Affordance | Type | Detail |
|------------|------|--------|
| `Daan::Core::Hook` module | Non-UI | `included` callback registers class in `Registry`; provides `applies_to_tool?` |
| `Daan::Core::Hook::Registry` | Non-UI | Class-level hash of registered hook classes; `register(klass)`, `agent_hooks(names)`, `tool_hooks` |
| `hooks:` frontmatter key | Non-UI | `Daan::Agent` struct reads `hooks:` list of Ruby constant name strings from agent `.md` YAML frontmatter |
| ConversationRunner: load hooks | Non-UI | At conversation start, resolve hook names via `Object.const_get(name).new` + all registered tool hooks |
| ConversationRunner: `before_llm_call` | Non-UI | Before each LLM call, dispatch `before_llm_call(chat:, last_tool_calls:)` to all hooks |
| `Daan::Core::Shaping` | Non-UI | `include Daan::Core::Hook`; `before_llm_call` injects `visible: false` ripple check if last turn included `update_document` |
| `ryan_singer.md` agent | Non-UI | Stub agent definition with `hooks: [Daan::Core::Shaping]` and `model:`, `tools:` |

---

## Slice 2: Full lifecycle + tool hooks

**Demo:** A `AuditLogHook` (or test hook) registered with `applies_to_tools %w[bash]` fires `after_tool_call` whenever any agent calls `Bash` — verifiable in logs.

| Affordance | Type | Detail |
|------------|------|--------|
| `Daan::Core::Hook.module(applies_to:)` | Non-UI | Factory for tool hooks; accepts tool class references; `applies_to_tool?` compares via `.tool_name` |
| ConversationRunner: `before_conversation` | Non-UI | Dispatch to all hooks before first LLM call |
| ConversationRunner: `before_tool_call` | Non-UI | Dispatch to applicable hooks before each tool execution |
| ConversationRunner: `after_tool_call` | Non-UI | Dispatch to applicable hooks after each tool execution |
| ConversationRunner: `after_conversation` | Non-UI | Dispatch to all hooks after conversation ends (complete/block/fail), passing `status:` |
| Tool hook auto-discovery | Non-UI | Zeitwerk loads all hook classes on boot; `include Daan::Core::Hook` registers on load — no directory scanning needed |
