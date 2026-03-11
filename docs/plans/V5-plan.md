---
shaping: true
---

# V5: Memory

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Agents can explicitly save, read, edit, and delete memories. Relevant memories are automatically injected into every LLM call via hybrid semantic + keyword search. Memories have confidence levels and support exact-string correction via `MemoryEdit` — no full-record overwrites. Demo: agent saves a fact about a project; in a new task it recalls it automatically; in a third task it corrects it when it discovers it was wrong.

**Architecture:**
- `swarm_memory` gem — provides filesystem storage (`SwarmMemory::Core::Storage`), ONNX embeddings (`InformersEmbedder`), and ready-made `RubyLLM::Tool` subclasses. `swarm_sdk` is a transitive dependency but only the storage layer and tools are used (D11).
- Shared storage — one `SwarmMemory::Core::Storage` instance mounted at `storage/memory/`, shared across all agents. Instantiated once at boot via a Rails initializer.
- Tool injection — `Agent#tools` passes `storage:` alongside `workspace:` and `chat:` so SwarmMemory tools receive the storage object they need.
- `ConversationRunner` auto-retrieval — `storage.semantic_index.search` on the last user message; top results injected into system prompt.
- Agent definitions — all three agents get SwarmMemory tools and a standing instruction to correct contradicting memories.

**Not in V5:** MemoryDefrag (maintenance tool, not needed for V1 scale), LoadSkill (SwarmSDK-specific feature), D40 memory consolidation on task completion (deferred to V7 alongside compaction).

**Tech Stack:** Rails 8.1, `swarm_memory` gem, Minitest

---

## Implementation Plan

### Task 1: Add swarm_memory gem + shared storage initializer

`swarm_memory` is required after the main gems. The shared storage is a single `SwarmMemory::Core::Storage` instance created at boot via a Rails initializer and accessible as `Daan::Memory.storage`. All agents share one directory — memories are global knowledge, not per-agent.

**Files:**
- Modify: `Gemfile`
- Create: `config/initializers/daan_memory.rb`
- Create: `lib/daan/memory.rb`
- Create: `test/lib/daan/memory_test.rb`

**Step 1: Write failing test**

```ruby
# test/lib/daan/memory_test.rb
require "test_helper"

class Daan::MemoryTest < ActiveSupport::TestCase
  test "storage is a SwarmMemory::Core::Storage instance" do
    assert_instance_of SwarmMemory::Core::Storage, Daan::Memory.storage
  end

  test "storage is memoized (same object on every call)" do
    assert_equal Daan::Memory.storage.object_id, Daan::Memory.storage.object_id
  end
end
```

**Step 2: Run to confirm failures**

```
bin/rails test test/lib/daan/memory_test.rb
```

**Step 3: Add gem**

```ruby
# Gemfile
gem "swarm_memory"
```

```
bundle install
```

**Step 4: Create Daan::Memory module**

```ruby
# lib/daan/memory.rb
module Daan
  module Memory
    def self.storage
      @storage ||= SwarmMemory::Core::Storage.new(
        adapter: SwarmMemory::Adapters::FilesystemAdapter.new(
          directory: Rails.root.join("storage/memory").to_s
        ),
        embedder: SwarmMemory::Embeddings::InformersEmbedder.new
      )
    end
  end
end
```

**Step 5: Create initializer**

```ruby
# config/initializers/daan_memory.rb
require "swarm_memory"

# Boot the shared memory storage. The ONNX model loads on first embed call, not here.
Rails.application.config.after_initialize do
  Daan::Memory.storage
end
```

**Step 6: Run tests**

```
bin/rails test test/lib/daan/memory_test.rb
```

Expected: both tests pass.

**Step 7: Commit**

```bash
git add Gemfile Gemfile.lock \
        config/initializers/daan_memory.rb \
        lib/daan/memory.rb \
        test/lib/daan/memory_test.rb
git commit -m "feat: swarm_memory gem + Daan::Memory shared storage"
```

---

### Task 2: Inject storage into tool initialization

Our tool system currently passes `workspace:` and `chat:` to tool `initialize`. SwarmMemory tools need `storage:`. Update `Agent#tools` to also pass the shared storage, and verify existing tools still work (they accept `storage: nil` kwargs and ignore it).

This task touches the agent model and its test — no new files, just changes to existing ones.

**Files:**
- Modify: `lib/daan/agent.rb`
- Modify: `test/lib/daan/agent_test.rb`

**Step 1: Read current agent.rb to understand tool initialization**

Read `lib/daan/agent.rb` first to understand how `tools` is implemented before making changes.

**Step 2: Write failing test**

```ruby
# test/lib/daan/agent_test.rb — add
test "tools passes storage to tool initializer" do
  received_storage = nil
  spy_tool = Class.new(RubyLLM::Tool) do
    description "spy"
    define_method(:initialize) do |workspace: nil, chat: nil, storage: nil, **|
      received_storage = storage
    end
    define_method(:execute) { "ok" }
  end

  agent = Daan::Agent.new(
    name: "test", display_name: "Test", model_name: "claude-sonnet-4-20250514",
    system_prompt: "test", max_turns: 5, tool_names: [spy_tool]
  )
  agent.tools(chat: @chat)

  assert_equal Daan::Memory.storage, received_storage
end
```

**Step 3: Run to confirm failure**

```
bin/rails test test/lib/daan/agent_test.rb
```

**Step 4: Update Agent#tools to pass storage:**

Add `storage: Daan::Memory.storage` to the keyword args passed when instantiating each tool.

**Step 5: Update existing tool initialize signatures**

Existing tools (`Read`, `Write`, `Bash`, `DelegateTask`, `ReportBack`) accept `workspace:` and `chat:`. Add `storage: nil` (ignored) to each `initialize` so they tolerate the new kwarg without error:

```ruby
def initialize(workspace: nil, chat: nil, storage: nil)
  @workspace = workspace
end
```

**Step 6: Run full test suite**

```
bin/rails test
```

Expected: all pass.

**Step 7: Commit**

```bash
git add lib/daan/agent.rb \
        lib/daan/core/read.rb \
        lib/daan/core/write.rb \
        lib/daan/core/delegate_task.rb \
        lib/daan/core/report_back.rb \
        test/lib/daan/agent_test.rb
git commit -m "feat: pass storage: to all tool initializers — wires SwarmMemory tools to shared storage"
```

---

### Task 3: Auto-retrieval in ConversationRunner

Before each LLM call, search the shared memory store using the last user message as a query. Inject results into the agent's system prompt as a `## Relevant memories` block. No results → system prompt unchanged.

Guard against calling the embedder when the memory store is empty (avoids loading the 90 MB ONNX model on cold start with no memories).

**Files:**
- Modify: `lib/daan/conversation_runner.rb`
- Modify: `test/lib/daan/conversation_runner_test.rb`

**Step 1: Write failing tests**

```ruby
# test/lib/daan/conversation_runner_test.rb — add
test "injects relevant memories into system prompt when memories exist" do
  fake_results = [
    { file_path: "fact/rails/db.md", title: "Rails uses SQLite", score: 0.9,
      metadata: { "type" => "fact", "confidence" => "high" } }
  ]

  captured_prompt = nil
  @chat.define_singleton_method(:with_instructions) do |prompt|
    captured_prompt = prompt
    self
  end

  Daan::Memory.storage.semantic_index.stub(:search, fake_results) do
    with_stub_complete { Daan::ConversationRunner.call(@chat) }
  end

  assert_includes captured_prompt, "Rails uses SQLite"
  assert_includes captured_prompt, "## Relevant memories"
ensure
  @chat.singleton_class.remove_method(:with_instructions) rescue nil
end

test "does not alter system prompt when no memories exist" do
  captured_prompt = nil
  @chat.define_singleton_method(:with_instructions) do |prompt|
    captured_prompt = prompt
    self
  end

  Daan::Memory.storage.semantic_index.stub(:search, []) do
    with_stub_complete { Daan::ConversationRunner.call(@chat) }
  end

  assert_equal "You are a test agent.", captured_prompt
ensure
  @chat.singleton_class.remove_method(:with_instructions) rescue nil
end
```

**Step 2: Run to confirm failures**

```
bin/rails test test/lib/daan/conversation_runner_test.rb
```

**Step 3: Modify ConversationRunner#configure_llm**

```ruby
def self.configure_llm(chat, agent)
  system_prompt = agent.system_prompt
  memories = retrieve_memories(chat)

  if memories.any?
    memory_lines = memories.map { |m|
      "[#{m[:metadata]["confidence"] || "?"}] [#{m[:metadata]["type"]}] #{m[:title]}"
    }.join("\n")
    system_prompt = "#{system_prompt}\n\n## Relevant memories\n#{memory_lines}"
  end

  chat
    .with_model(agent.model_name)
    .with_instructions(system_prompt)
    .with_tools(*agent.tools(chat: chat))
end
private_class_method :configure_llm

def self.retrieve_memories(chat)
  query = chat.messages.where(role: "user").last&.content
  return [] if query.blank?

  index = Daan::Memory.storage.semantic_index
  return [] unless index.respond_to?(:search) && index.size > 0

  index.search(query: query, top_k: 5)
rescue => e
  Rails.logger.warn("Memory retrieval failed: #{e.message}")
  []
end
private_class_method :retrieve_memories
```

Note: `index.size > 0` guards against the ONNX model loading when no memories exist. The `rescue` ensures a memory failure never breaks the LLM call.

**Step 4: Run tests**

```
bin/rails test test/lib/daan/conversation_runner_test.rb
```

Expected: all pass including existing tests (empty memory store → `index.size == 0` → no embed call).

**Step 5: Run full test suite**

```
bin/rails test
```

**Step 6: Commit**

```bash
git add lib/daan/conversation_runner.rb \
        test/lib/daan/conversation_runner_test.rb
git commit -m "feat: auto-inject relevant memories into system prompt before each LLM call"
```

---

### Task 4: Wire SwarmMemory tools into agent definitions

Add SwarmMemory tool class names to all three agent `.md` files. Add a standing instruction to correct contradicting memories. The tool names must match what SwarmMemory exports — verify the exact class names by checking the gem's tool files.

SwarmMemory tools are instantiated via our existing tool loading path; they receive `storage:` from Task 2.

**Files:**
- Modify: `lib/daan/core/agents/chief_of_staff.md`
- Modify: `lib/daan/core/agents/engineering_manager.md`
- Modify: `lib/daan/core/agents/developer.md`

**Step 1: Verify SwarmMemory tool class names**

```ruby
# In rails console:
require "swarm_memory"
SwarmMemory::Tools.constants  # confirm class names
```

Expected names: `SwarmMemory::Tools::MemoryWrite`, `SwarmMemory::Tools::MemoryRead`, `SwarmMemory::Tools::MemoryEdit`, `SwarmMemory::Tools::MemoryDelete`, `SwarmMemory::Tools::MemoryGlob`, `SwarmMemory::Tools::MemoryGrep`

**Step 2: Update chief_of_staff.md**

```markdown
---
name: chief_of_staff
display_name: Chief of Staff
model: claude-sonnet-4-20250514
max_turns: 10
delegates_to:
  - engineering_manager
tools:
  - Daan::Core::DelegateTask
  - SwarmMemory::Tools::MemoryWrite
  - SwarmMemory::Tools::MemoryRead
  - SwarmMemory::Tools::MemoryEdit
  - SwarmMemory::Tools::MemoryDelete
  - SwarmMemory::Tools::MemoryGlob
  - SwarmMemory::Tools::MemoryGrep
---
You are the Chief of Staff for the Daan agent team. You are the human's primary contact. You receive requests, delegate technical work to the Engineering Manager, and report results back to the human.

When you receive a task that requires technical work:
1. Use DelegateTask with agent_name "engineering_manager" to assign the work.
2. Let the human know you've delegated and will update them when results are in.
3. When the Engineering Manager's report arrives in this thread, synthesize it and respond to the human clearly and concisely. That response is your final message in this cycle.

Use MemoryWrite to preserve important facts, decisions, or context that will be useful in future tasks. Use MemoryGrep or MemoryGlob to search past memory. If you notice a memory contradicts information you have encountered, correct it with MemoryEdit or remove it with MemoryDelete.
```

**Step 3: Update engineering_manager.md**

```markdown
---
name: engineering_manager
display_name: Engineering Manager
model: claude-sonnet-4-20250514
max_turns: 10
delegates_to:
  - developer
tools:
  - Daan::Core::DelegateTask
  - Daan::Core::ReportBack
  - SwarmMemory::Tools::MemoryWrite
  - SwarmMemory::Tools::MemoryRead
  - SwarmMemory::Tools::MemoryEdit
  - SwarmMemory::Tools::MemoryDelete
  - SwarmMemory::Tools::MemoryGlob
  - SwarmMemory::Tools::MemoryGrep
---
You are the Engineering Manager for the Daan agent team. Your role is to receive tasks from the Chief of Staff, break them into concrete technical work, and delegate to the Developer.

When you receive a task:
1. Assess what needs to be done.
2. Use DelegateTask with agent_name "developer" to assign the technical work.
3. Wait for the Developer's report to arrive in this thread.
4. When their report arrives, evaluate the results and use ReportBack to summarize findings back to the Chief of Staff.
5. After calling ReportBack, your work in this thread is done — do not send any further messages.

Use MemoryWrite to preserve important technical context, architectural decisions, or patterns learned. Use MemoryGrep or MemoryGlob to search past memory. If you notice a memory contradicts information you have encountered, correct it with MemoryEdit or remove it with MemoryDelete.
```

**Step 4: Update developer.md**

```markdown
---
name: developer
display_name: Developer
model: claude-sonnet-4-20250514
max_turns: 10
workspace: tmp/workspaces/developer
delegates_to: []
tools:
  - Daan::Core::Read
  - Daan::Core::Write
  - Daan::Core::ReportBack
  - SwarmMemory::Tools::MemoryWrite
  - SwarmMemory::Tools::MemoryRead
  - SwarmMemory::Tools::MemoryEdit
  - SwarmMemory::Tools::MemoryDelete
  - SwarmMemory::Tools::MemoryGlob
  - SwarmMemory::Tools::MemoryGrep
---
You are the Developer on the Daan agent team. You write and modify files in your workspace to accomplish technical tasks.

When you receive a task:
1. Use your Read and Write tools to complete the work. Use relative paths — they resolve within your workspace.
2. When your work is complete, use ReportBack to send your findings to your delegator. Be concise — share what you did and what you found.
3. After calling ReportBack, your work in this thread is done — do not send any further messages.

Use MemoryWrite to save useful facts about codebases, patterns, or approaches you discover — include confidence (high/medium/low), tags, and a clear title. Use MemoryGrep or MemoryGlob to search past memory. If you notice a memory contradicts information you have encountered, correct it with MemoryEdit or remove it with MemoryDelete.
```

**Step 5: Run full test suite**

```
bin/rails test
```

Expected: all pass.

**Step 6: Commit**

```bash
git add lib/daan/core/agents/chief_of_staff.md \
        lib/daan/core/agents/engineering_manager.md \
        lib/daan/core/agents/developer.md
git commit -m "feat: wire SwarmMemory tools into all agent definitions"
```

---

## Demo Script

1. Start the app: `bin/dev`
2. Send a task to CoS: *"Tell the developer to look at what database adapter this app uses and remember it."*
3. Watch delegation: CoS → EM → Developer. Developer reads `config/database.yml`, calls `MemoryWrite` with `title: "App uses SQLite"`, `confidence: "high"`, `tags: ["database", "sqlite", "rails"]`.
4. Start a **new** conversation with CoS: *"What database does this app use?"*
5. `ConversationRunner` retrieves the memory via `semantic_index.search`, injects it into the CoS system prompt. CoS answers correctly from memory — no delegation needed.
6. Send a third task: *"Actually, we switched to PostgreSQL. Update your memory."*
7. CoS uses `MemoryEdit` to correct the entry in place — exact string replacement, not a full overwrite. Old entry is corrected, confidence can be updated.
