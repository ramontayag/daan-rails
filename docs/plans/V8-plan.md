---
shaping: true
---

# V8: CoS Discovers Team

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** The Chief of Staff can call `ListAgents` to get a live view of all registered agents — their names, descriptions, and tool lists. This gives the CoS dynamic awareness of the team without needing its prompt manually updated when new agents are added.

**Architecture:**
- `Daan::Core::ListAgents` — new tool, no params, reads `AgentRegistry.all`, returns a formatted string with each agent's name, description, and tools.
- `lib/daan/core/agents/chief_of_staff.md` — updated to include `Daan::Core::ListAgents` in its tool list.
- No new DB columns, no new routes, no UI changes — the tool call appears as an observable block in the CoS thread via the existing tool call rendering.

**Not in V8:** Filtering agents by capability, structured JSON output, per-agent detail tool.

**Tech Stack:** Rails 8.1, Minitest

---

## Implementation Plan

### Task 1: `Daan::Core::ListAgents` tool

**Files:**
- Create: `lib/daan/core/list_agents.rb`
- Create: `test/lib/daan/core/list_agents_test.rb`

**Step 1: Write failing tests**

```ruby
# test/lib/daan/core/list_agents_test.rb
require "test_helper"

class Daan::Core::ListAgentsTest < ActiveSupport::TestCase
  test "returns formatted list of all registered agents" do
    agent = Daan::Agent.new(
      name: "developer",
      display_name: "Developer",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You write code.",
      max_turns: 10,
      base_tools: [Daan::Core::Read]
    )
    Daan::AgentRegistry.register(agent)

    tool = Daan::Core::ListAgents.new
    result = tool.execute

    assert_includes result, "Developer (developer)"
    assert_includes result, "Daan::Core::Read"
  end

  test "returns message when no agents registered" do
    tool = Daan::Core::ListAgents.new
    result = tool.execute
    assert_includes result, "No agents"
  end
end
```

**Step 2: Run to confirm failures**

```
bin/rails test test/lib/daan/core/list_agents_test.rb
```

**Step 3: Implement**

```ruby
# lib/daan/core/list_agents.rb
module Daan
  module Core
    class ListAgents < RubyLLM::Tool
      description "List all registered agents on the team — their names, descriptions, and tools. " \
                  "Use this to understand who is available and what each agent can do before delegating."

      def initialize(workspace: nil, chat: nil, storage: nil, agent_name: nil, allowed_commands: nil)
      end

      def execute
        agents = Daan::AgentRegistry.all
        return "No agents are currently registered." if agents.empty?

        agents.map do |agent|
          tools = agent.base_tools.map(&:name).join(", ")
          tools_line = tools.empty? ? "" : "\n  Tools: #{tools}"
          "#{agent.display_name} (#{agent.name})#{tools_line}"
        end.join("\n\n")
      end
    end
  end
end
```

**Step 4: Run tests**

```
bin/rails test test/lib/daan/core/list_agents_test.rb
```

**Step 5: Run full suite**

```
bin/rails test && bin/rails test:system
```

**Step 6: Commit**

```bash
git add lib/daan/core/list_agents.rb test/lib/daan/core/list_agents_test.rb
git commit -m "feat: ListAgents tool — CoS can discover team capabilities from AgentRegistry"
```

---

### Task 2: Wire ListAgents into CoS definition

**Files:**
- Modify: `lib/daan/core/agents/chief_of_staff.md`

**Step 1: Update chief_of_staff.md**

Add `Daan::Core::ListAgents` to the tools list. Add a note to the system prompt instructing the CoS to call it when it needs to know who to delegate to.

```markdown
tools:
  - Daan::Core::DelegateTask
  - Daan::Core::ListAgents
  - SwarmMemory::Tools::MemoryWrite
  - SwarmMemory::Tools::MemoryRead
  - SwarmMemory::Tools::MemoryEdit
  - SwarmMemory::Tools::MemoryDelete
  - SwarmMemory::Tools::MemoryGlob
  - SwarmMemory::Tools::MemoryGrep
```

Add to the system prompt body:

```
When you need to delegate a task and are unsure who to assign it to, call ListAgents first
to get a current view of the team — their roles and capabilities.
```

**Step 2: Run full suite**

```
bin/rails test && bin/rails test:system
```

**Step 3: Commit**

```bash
git add lib/daan/core/agents/chief_of_staff.md
git commit -m "feat: wire ListAgents into CoS — dynamic team discovery without prompt maintenance"
```

---

## Demo Script

1. Start the app: `bin/dev`
2. Message the CoS: *"Who is on your team and what can they do?"*
3. Watch the CoS thread — a `ListAgents` tool call block appears
4. CoS responds with a description of each agent, their role, and their tools
5. Optional: switch to CoS perspective to see the tool call from its point of view
