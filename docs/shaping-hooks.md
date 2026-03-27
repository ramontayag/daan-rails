---
shaping: true
---

# Agent Hooks — Shaping

## Problem

ConversationRunner has no extension points. Injecting workflow-specific behavior (e.g. ripple check reminders, audit logging, rate limiting) requires modifying ConversationRunner directly, coupling generic infrastructure to domain-specific concerns.

## Outcome

A hooks system where agents opt into named hooks via frontmatter, and tool-level hooks fire automatically for specific tools across all agents — without coupling hook classes to specific agents or deployments.

---

## Requirements (R)

| ID | Requirement | Status |
|----|-------------|--------|
| R0 | ConversationRunner dispatches to hooks at defined lifecycle points | Core goal |
| R1 | Agents opt into hooks by declaring them in frontmatter | Must-have |
| R2 | Hook classes are generic — no knowledge of which agents use them | Must-have |
| R3 | Tool hooks fire for a named tool across all agents, always-on | Must-have |
| R4 | Tool hooks are auto-discovered — no manual registration | Must-have |
| R5 | Lifecycle covers: before_conversation, before_llm_call, before_tool_call, after_tool_call, after_conversation | Must-have |
| R6 | Hooks can inject invisible messages into the conversation (`visible: false`) | Must-have |

---

## A: Two-tier hooks with frontmatter opt-in and include-based registration

### Registration

Two inclusion forms depending on hook type:

**Agent hooks** — plain include. No configuration needed; the agent frontmatter controls which agents opt in.

```ruby
class Daan::Core::Shaping
  include Daan::Core::Hook
```

**Tool hooks** — `.module(applies_to:)`. Declares which tool classes trigger this hook. Uses class references (not strings), so `.tool_name` does the comparison — no magic strings anywhere.

```ruby
class Daan::Core::AuditLog
  include Daan::Core::Hook.module(applies_to: [Daan::Core::Bash, Daan::Core::Write])
```

The distinction is meaningful: the call site communicates which kind of hook you're writing.

```ruby
module Daan
  module Core
    module Hook
      def self.included(base)
        Registry.register(base)
      end

      def self.module(applies_to:)
        tool_classes = applies_to
        Module.new do
          def self.included(base)
            Daan::Core::Hook::Registry.register(base)
            base.instance_variable_set(:@applies_to_tool_classes, tool_classes)
          end
        end
      end

      def before_llm_call(chat:, last_tool_calls:); end

      def applies_to_tool?(tool_name)
        tool_classes = self.class.instance_variable_get(:@applies_to_tool_classes)
        return false unless tool_classes
        tool_classes.any? { |klass| klass.tool_name == tool_name }
      end
    end
  end
end
```

### Agent hooks

Declared in agent frontmatter as full Ruby constant strings — the same pattern tools already use. No naming convention, no magic.

```yaml
# lib/daan/core/agents/ryan_singer.md
hooks:
  - Daan::Core::Shaping
```

ConversationRunner resolves each name with `Object.const_get(name).new`. The hook implements whichever lifecycle methods it needs:

```ruby
module Daan
  module Core
    class Shaping
      include Daan::Core::Hook

      # Fires once before each LLM call. If the previous turn updated any documents,
      # inject a single ripple check reminder — rather than one message per update_document
      # call, which would be noisy and redundant.
      def before_llm_call(chat:, last_tool_calls:)
        return unless last_tool_calls.any? { |tc| tc.name == Daan::Core::UpdateDocument.tool_name }
        # Use chat.messages.create! directly — NOT Daan::CreateMessage,
        # which enqueues LlmJob for user-role messages.
        chat.messages.create!(
          role: "user",
          content: "[System] Ripple check: you updated document(s) in the previous turn. " \
                   "Verify changes are consistent with related documents " \
                   "(shaping → slices → slice plans) before continuing.",
          visible: false
        )
      end
    end
  end
end
```

### Tool hooks

Include `Daan::Core::Hook` and declare `applies_to_tools`. Fire for all agents automatically — no frontmatter needed.

```ruby
module Daan
  module Core
    class AuditLog
      include Daan::Core::Hook.module(applies_to: [Daan::Core::Bash, Daan::Core::Write])

      def after_tool_call(tool_name:, chat:, result:)
        # log to audit trail
      end
    end
  end
end
```

### ConversationRunner

Loads agent hooks (from frontmatter) + all registered tool hooks at conversation start, dispatches at each lifecycle point:

```ruby
hooks = Daan::Core::Hook::Registry.agent_hooks(agent.hook_names) +
        Daan::Core::Hook::Registry.tool_hooks

hooks.each { |h| h.before_conversation(chat: chat) }

loop do
  hooks.each { |h| h.before_llm_call(chat: chat, last_tool_calls: last_tool_calls) }
  # LLM call

  # tool execution
  hooks.select { |h| h.applies_to_tool?(tool_name) }
       .each { |h| h.before_tool_call(tool_name:, chat:, args:) }
  result = tool.execute
  hooks.select { |h| h.applies_to_tool?(tool_name) }
       .each { |h| h.after_tool_call(tool_name:, chat:, result:) }
end

hooks.each { |h| h.after_conversation(chat: chat, status:) }
```

---

## Fit Check

| Req | Requirement | Status | A |
|-----|-------------|--------|---|
| R0 | ConversationRunner dispatches to hooks at defined lifecycle points | Core goal | ✅ |
| R1 | Agents opt into hooks by declaring them in frontmatter | Must-have | ✅ |
| R2 | Hook classes are generic — no knowledge of which agents use them | Must-have | ✅ |
| R3 | Tool hooks fire for a named tool across all agents, always-on | Must-have | ✅ |
| R4 | Tool hooks are auto-discovered | Must-have | ✅ |
| R5 | Lifecycle: before_conversation, before_llm_call, before_tool_call, after_tool_call, after_conversation | Must-have | ✅ |
| R6 | Hooks can inject invisible messages | Must-have | ✅ |

---

## Decisions

- **Error handling:** Log and continue. A misbehaving hook must never halt a conversation. This matches Claude Code's behavior: hook errors are logged but non-fatal. ConversationRunner wraps each hook dispatch in a rescue, logs the exception, and proceeds.
