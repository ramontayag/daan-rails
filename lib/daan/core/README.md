# Daan::Core

Core agent infrastructure. Agents are defined in `agents/*.md`, loaded at boot via `AgentLoader`, and stored in `AgentRegistry`. `ConversationRunner` drives each LLM turn.

## Allowed Commands

`Daan::Core::Bash` exposes a shell tool to agents. A global allowlist (`Bash::ALLOWED_COMMANDS`) defines which binaries are available. Agents inherit the full list by default.

Restrict an agent to a subset via `allowed_commands` in its frontmatter:

```yaml
# agents/developer.md
allowed_commands:
  - git
  - gh
```

When `allowed_commands` is omitted, the agent gets every command in the global list. When set, it must be a strict subset — declaring a command not in the global list raises `ArgumentError` at load time.

## Hooks

Hooks let you inject behavior at defined points in the conversation lifecycle without modifying `ConversationRunner`.

### Lifecycle

One lifecycle point is implemented today:

| Point | When | Args |
|-------|------|------|
| `before_llm_call` | Before each LLM call, after tool results are in | `chat:`, `last_tool_calls:` |

### Two kinds of hooks

**Agent hooks** — opted into per agent via frontmatter. The agent controls which hooks apply.

```ruby
class Daan::Core::Shaping
  include Daan::Core::Hook

  def before_llm_call(chat:, last_tool_calls:)
    # fires before every LLM call for agents that declare this hook
  end
end
```

```yaml
# agents/ryan_singer.md
hooks:
  - Daan::Core::Shaping
```

**Tool hooks** — always-on, fire for a specific tool across all agents. Declare which tools trigger them via `.module(applies_to:)`.

```ruby
class Daan::Core::AuditLog
  include Daan::Core::Hook.module(applies_to: [Daan::Core::Bash, Daan::Core::Write])

  def after_tool_call(tool_name:, chat:, result:)
    # fires whenever any agent calls Bash or Write
  end
end
```

Tool hooks are auto-discovered — Zeitwerk loads them on boot when they `include Daan::Core::Hook`.

### Hook names in frontmatter

Use the full Ruby constant string — the same convention tools already use:

```yaml
hooks:
  - Daan::Core::Shaping   # correct
  - shaping               # will raise NameError at runtime
```

### Error handling

A hook that raises is logged and skipped — it never aborts the conversation.

### `tool_name`

Every tool exposes `tool_name` as a class method, returning the RubyLLM-derived name (e.g. `"daan--core--update_document"`). This is what gets stored in `ToolCall.name` and what hooks should compare against — never hardcode the string.

```ruby
last_tool_calls.any? { |tc| tc.name == Daan::Core::UpdateDocument.tool_name }
```
