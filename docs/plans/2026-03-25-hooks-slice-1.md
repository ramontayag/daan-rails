# Hooks Slice 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `before_llm_call` hook lifecycle to ConversationRunner, wire up a `Daan::Core::Shaping` that injects a ripple-check reminder after `update_document` calls, and create a stub `ryan_singer` agent that opts in.

**Architecture:** Agents declare `hooks: [Daan::Core::Shaping]` in their frontmatter — full Ruby constant strings, the same pattern tools already use. `ConversationRunner` resolves them with `Object.const_get(name).new` and calls `before_llm_call(chat:, last_tool_calls:)` before each `chat.step`. `Daan::Core::Shaping` checks `last_tool_calls` for `update_document` and creates a `visible: false` user message directly (bypassing `Daan::CreateMessage` which would enqueue a second `LlmJob`).

**Tech Stack:** Rails 8.1, Minitest, `ToolCall` AR model, direct `chat.messages.create!` for invisible system messages.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `lib/daan/core/tool.rb` | `Daan::Core::Tool` module; `.module(timeout:)` factory; `tool_name` class method; raises if included directly |
| Modify | `lib/daan/core/*.rb` (all 12 tools) | Replace `extend ToolTimeout` + `tool_timeout_seconds X` with `include Daan::Core::Tool.module(timeout: X)` |
| Create | `lib/daan/core/hook.rb` | `Daan::Core::Hook` module with `Registry`; `included` callback registers classes; default no-op lifecycle methods |
| Create | `lib/daan/core/shaping.rb` | `Daan::Core::Shaping`; `before_llm_call` injects ripple check using `Daan::Core::UpdateDocument.tool_name` |
| Create | `lib/daan/core/agents/ryan_singer.md` | Stub RyanSinger agent with `hooks: [Daan::Core::Shaping]` |
| Modify | `lib/daan/agent.rb` | Add `hook_names` field (array of strings, default `[]`) |
| Modify | `lib/daan/agent_loader.rb` | Parse `hooks:` frontmatter key into `hook_names` |
| Modify | `lib/daan/conversation_runner.rb` | Load hooks via Registry; dispatch `before_llm_call(chat:, last_tool_calls:)` before `RunStep` |
| Create | `test/lib/daan/core/tool_test.rb` | Tests for `Daan::Core::Tool` |
| Create | `test/lib/daan/core/hook_test.rb` | Tests for `Daan::Core::Hook` module and `Registry` |
| Create | `test/lib/daan/core/shaping_test.rb` | Tests for `Daan::Core::Shaping` |
| Modify | `test/lib/daan/conversation_runner_test.rb` | Test that hooks receive `before_llm_call` with correct args |

---

## Task 0: `Daan::Core::Tool` module

Every tool currently does `extend ToolTimeout` + `tool_timeout_seconds X` as two separate lines. `Daan::Core::Tool` consolidates this and adds `tool_name` — a class method returning the RubyLLM-derived tool name (e.g. `"daan--core--update_document"`), which is what gets stored in the `ToolCall.name` column.

Plain `include Daan::Core::Tool` is forbidden — raises immediately with a helpful message. Only `include Daan::Core::Tool.module(timeout:)` is valid, keeping configuration explicit at every call site.

`ToolTimeout` stays unchanged as the underlying mechanism; `Daan::Core::Tool` wraps it.

**Files:**
- Create: `lib/daan/core/tool.rb`
- Create: `test/lib/daan/core/tool_test.rb`
- Modify: all 12 tool files in `lib/daan/core/`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/lib/daan/core/tool_test.rb
require "test_helper"

class Daan::Core::ToolTest < ActiveSupport::TestCase
  test "raises if included directly without .module" do
    assert_raises(RuntimeError, /Use.*\.module/) do
      Class.new(RubyLLM::Tool) { include Daan::Core::Tool }
    end
  end

  test ".module(timeout:) adds tool_timeout_seconds to the including class" do
    klass = Class.new(RubyLLM::Tool) { include Daan::Core::Tool.module(timeout: 42.seconds) }
    assert_equal 42.seconds, klass.tool_timeout_seconds
  end

  test ".module(timeout:) adds tool_name class method returning RubyLLM-derived name" do
    klass = Class.new(RubyLLM::Tool) do
      include Daan::Core::Tool.module(timeout: 5.seconds)
    end
    assert_respond_to klass, :tool_name
    assert_equal klass.new.name, klass.tool_name
  end

  test "Daan::Core::UpdateDocument.tool_name returns the stored tool call name" do
    assert_equal Daan::Core::UpdateDocument.new.name, Daan::Core::UpdateDocument.tool_name
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/lib/daan/core/tool_test.rb
```
Expected: `NameError: uninitialized constant Daan::Core::Tool`

- [ ] **Step 3: Implement**

```ruby
# lib/daan/core/tool.rb
module Daan
  module Core
    module Tool
      def self.included(_base)
        raise "Use `include Daan::Core::Tool.module(timeout:)` — plain include is not allowed"
      end

      def self.module(timeout:)
        t = timeout
        Module.new do
          def self.included(base)
            base.extend(Daan::Core::ToolTimeout)
            base.extend(Daan::Core::Tool::ClassMethods)
            base.tool_timeout_seconds(t)
          end
        end
      end

      module ClassMethods
        def tool_name
          new.name
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
bin/rails test test/lib/daan/core/tool_test.rb
```
Expected: 4 tests, 0 failures

- [ ] **Step 5: Update all 12 tool files**

Replace `extend ToolTimeout` + `tool_timeout_seconds X` with `include Daan::Core::Tool.module(timeout: X)` in each file:

| File | Timeout |
|------|---------|
| `lib/daan/core/bash.rb` | `10.seconds` |
| `lib/daan/core/create_agent.rb` | `10.seconds` |
| `lib/daan/core/create_document.rb` | `5.seconds` |
| `lib/daan/core/create_steps.rb` | `10.seconds` |
| `lib/daan/core/delegate_task.rb` | `10.seconds` |
| `lib/daan/core/edit_agent.rb` | `10.seconds` |
| `lib/daan/core/list_agents.rb` | `10.seconds` |
| `lib/daan/core/promote_branch.rb` | `1.minute` |
| `lib/daan/core/read.rb` | `10.seconds` |
| `lib/daan/core/report_back.rb` | `10.seconds` |
| `lib/daan/core/update_document.rb` | `5.seconds` |
| `lib/daan/core/update_step.rb` | `10.seconds` |
| `lib/daan/core/write.rb` | `10.seconds` |

Example diff for `bash.rb`:
```ruby
# before
class Bash < RubyLLM::Tool
  extend ToolTimeout
  tool_timeout_seconds 10.seconds

# after
class Bash < RubyLLM::Tool
  include Daan::Core::Tool.module(timeout: 10.seconds)
```

- [ ] **Step 6: Run the full suite to confirm no regressions**

```bash
bin/rails test
```
Expected: all pass

- [ ] **Step 7: Commit**

```bash
git add lib/daan/core/tool.rb test/lib/daan/core/tool_test.rb lib/daan/core/bash.rb \
  lib/daan/core/create_agent.rb lib/daan/core/create_document.rb lib/daan/core/create_steps.rb \
  lib/daan/core/delegate_task.rb lib/daan/core/edit_agent.rb lib/daan/core/list_agents.rb \
  lib/daan/core/promote_branch.rb lib/daan/core/read.rb lib/daan/core/report_back.rb \
  lib/daan/core/update_document.rb lib/daan/core/update_step.rb lib/daan/core/write.rb
git commit -m "feat: add Daan::Core::Tool module with tool_name and explicit timeout"
```

---

## Task 1: `Daan::Core::Hook` module and `Registry`

`Daan::Core::Hook` is a module that hook classes include. Its `included` callback registers the including class in `Registry`. The module provides default no-op lifecycle methods. `Registry` stores all registered hook classes and provides `agent_hooks(names)` (resolves name strings to instances) and `tool_hooks` (returns instances of always-on hooks — empty in Slice 1, used in Slice 2).

Hook name resolution in `agent_hooks`: `"shaping"` → `Object.const_get("Daan::Core::Shaping")`. Zeitwerk auto-loads `app/hooks/shaping_hook.rb` when `Daan::Core::Shaping` is first referenced. `applies_to_tool?` is part of the module interface; it defaults to `false` (tool hooks opt in — Slice 2 concern).

**Files:**
- Create: `lib/daan/core/hook.rb`
- Create: `test/lib/daan/core/hook_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/lib/daan/core/hook_test.rb
require "test_helper"

class Daan::Core::HookTest < ActiveSupport::TestCase
  teardown { Daan::Core::Hook::Registry.clear }

  test "included class is registered in Registry" do
    klass = Class.new { include Daan::Core::Hook }
    assert_includes Daan::Core::Hook::Registry.all, klass
  end

  test "included class gets default no-op before_llm_call" do
    klass = Class.new { include Daan::Core::Hook }
    assert_nothing_raised { klass.new.before_llm_call(chat: nil, last_tool_calls: []) }
  end

  test "applies_to_tool? returns false for plain agent hook includes" do
    klass = Class.new { include Daan::Core::Hook }
    assert_equal false, klass.new.applies_to_tool?("anything")
  end

  test ".module(applies_to:) sets applies_to_tool? for listed tool classes" do
    klass = Class.new { include Daan::Core::Hook.module(applies_to: [Daan::Core::Bash]) }
    assert_equal true,  klass.new.applies_to_tool?(Daan::Core::Bash.tool_name)
    assert_equal false, klass.new.applies_to_tool?(Daan::Core::Write.tool_name)
  end

  test "Registry.agent_hooks resolves constant name strings to instances" do
    stub_hook = Class.new { include Daan::Core::Hook }
    Object.const_set("StubHook", stub_hook)
    instances = Daan::Core::Hook::Registry.agent_hooks(["StubHook"])
    assert_equal 1, instances.size
    assert_instance_of stub_hook, instances.first
  ensure
    Object.send(:remove_const, :StubHook) if Object.const_defined?(:StubHook)
  end

  test "Registry.tool_hooks returns only hooks included via .module(applies_to:)" do
    Class.new { include Daan::Core::Hook }  # agent hook — not a tool hook
    assert_equal [], Daan::Core::Hook::Registry.tool_hooks
  end

  test "Registry.clear removes all registered classes" do
    Class.new { include Daan::Core::Hook }
    Daan::Core::Hook::Registry.clear
    assert_empty Daan::Core::Hook::Registry.all
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/lib/daan/core/hook_test.rb
```
Expected: `NameError: uninitialized constant Daan::Core::Hook`

- [ ] **Step 3: Implement**

```ruby
# lib/daan/core/hook.rb
module Daan
  module Core
    module Hook
      # Agent hooks: plain include. No configuration needed.
      def self.included(base)
        Registry.register(base)
      end

      # Tool hooks: .module(applies_to: [ToolClass, ...]).
      # Uses class references — applies_to_tool? compares via .tool_name.
      def self.module(applies_to:)
        tool_classes = applies_to
        Module.new do
          def self.included(base)
            Daan::Core::Hook::Registry.register(base)
            base.instance_variable_set(:@applies_to_tool_classes, tool_classes)
          end
        end
      end

      # Default no-op lifecycle methods. Hook classes override what they need.
      def before_llm_call(chat:, last_tool_calls:); end

      # Returns true if this hook applies to the given tool name.
      # Agent hooks (plain include) always return false — they are not tool hooks.
      def applies_to_tool?(tool_name)
        tool_classes = self.class.instance_variable_get(:@applies_to_tool_classes)
        return false unless tool_classes
        tool_classes.any? { |klass| klass.tool_name == tool_name }
      end

      class Registry
        @registry = []

        class << self
          def register(klass)
            @registry << klass unless @registry.include?(klass)
          end

          # Resolve full Ruby constant name strings to fresh instances.
          # "Daan::Core::Shaping" => Object.const_get("Daan::Core::Shaping").new
          def agent_hooks(names)
            names.map { |name| Object.const_get(name).new }
          end

          # Returns instances of tool hooks (included via .module(applies_to:)).
          # Empty in Slice 1; populated in Slice 2.
          def tool_hooks
            @registry
              .select { |klass| klass.instance_variable_defined?(:@applies_to_tool_classes) }
              .map(&:new)
          end

          def all
            @registry.dup
          end

          def clear
            @registry = []
          end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
bin/rails test test/lib/daan/core/hook_test.rb
```
Expected: 6 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add lib/daan/core/hook.rb test/lib/daan/core/hook_test.rb
git commit -m "feat: add Daan::Core::Hook module with Registry"
```

---

## Task 2: `Daan::Core::Shaping`

`Daan::Core::Shaping` lives in `lib/daan/core/shaping.rb` — Zeitwerk maps this to the `Daan::Core::Shaping` constant, matching the full constant string declared in frontmatter (`hooks: [Daan::Core::Shaping]`). It must **not** use `Daan::CreateMessage` — that method enqueues `LlmJob` for user-role messages, which would trigger a recursive job mid-conversation. Use `chat.messages.create!` directly, the same pattern as `Chats::FinishOrReenqueue#warn_approaching_step_limit`.

**Files:**
- Create: `lib/daan/core/shaping.rb`
- Create: `test/lib/daan/core/shaping_test.rb`

- [ ] **Step 1: Write the failing tests**

```ruby
# test/lib/daan/core/shaping_test.rb
require "test_helper"

class Daan::Core::ShapingTest < ActiveSupport::TestCase
  setup do
    agent = Daan::Agent.new(
      name: "ryan_singer", display_name: "Ryan Singer",
      model_name: "claude-sonnet-4-6", system_prompt: "You shape.",
      max_steps: 20
    )
    Daan::AgentRegistry.register(agent)
    @chat = Chat.create!(agent_name: "ryan_singer")
    @hook = Daan::Core::Shaping.new
  end

  def call_hook(last_tool_calls: [])
    @hook.before_llm_call(chat: @chat, last_tool_calls: last_tool_calls)
  end

  test "does nothing when last_tool_calls is empty" do
    assert_no_difference -> { @chat.messages.count } do
      call_hook
    end
  end

  test "does nothing when last_tool_calls has no update_document call" do
    tc = build_tool_call("read_file")
    assert_no_difference -> { @chat.messages.count } do
      call_hook(last_tool_calls: [tc])
    end
  end

  test "injects a visible:false ripple-check message when update_document was called" do
    tc = build_tool_call("update_document")
    assert_difference -> { @chat.messages.count }, 1 do
      call_hook(last_tool_calls: [tc])
    end

    msg = @chat.messages.order(:id).last
    assert_equal "user", msg.role
    assert_equal false, msg.visible
    assert_includes msg.content, "Ripple check"
  end

  test "injects exactly one message even when multiple update_document calls in one turn" do
    tcs = [build_tool_call("update_document"), build_tool_call("update_document")]
    assert_difference -> { @chat.messages.count }, 1 do
      call_hook(last_tool_calls: tcs)
    end
  end

  test "does not enqueue LlmJob when injecting ripple check" do
    tc = build_tool_call("update_document")
    assert_no_enqueued_jobs only: LlmJob do
      call_hook(last_tool_calls: [tc])
    end
  end

  private

  # Build a minimal ToolCall-like double for the hook interface.
  # Daan::Core::Shaping only checks tc.name, so an OpenStruct suffices.
  def build_tool_call(name)
    OpenStruct.new(name: name)
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/lib/daan/core/shaping_test.rb
```
Expected: `NameError: uninitialized constant Daan::Core::Shaping`

- [ ] **Step 3: Implement**

```ruby
# lib/daan/core/shaping.rb
module Daan
  module Core
    class Shaping
      include Daan::Core::Hook

      RIPPLE_CHECK_CONTENT = "[System] Ripple check: you updated document(s) in the previous turn. " \
        "Verify your changes are consistent with related documents " \
        "(shaping → slices → slice plans) before continuing."

      def before_llm_call(chat:, last_tool_calls:)
        return unless last_tool_calls.any? { |tc| tc.name == Daan::Core::UpdateDocument.tool_name }

        # Use chat.messages.create! directly — NOT Daan::CreateMessage.
        # CreateMessage enqueues LlmJob for user-role messages, which would
        # trigger a recursive job mid-conversation.
        chat.messages.create!(role: "user", content: RIPPLE_CHECK_CONTENT, visible: false)
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
bin/rails test test/lib/daan/core/shaping_test.rb
```
Expected: 5 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add lib/daan/core/shaping.rb test/lib/daan/core/shaping_test.rb
git commit -m "feat: add Daan::Core::Shaping with before_llm_call ripple check"
```

---

## Task 3: `Agent` struct and `AgentLoader`

`Agent` needs a `hook_names` field (array of strings, default `[]`). `AgentLoader` reads `hooks:` from frontmatter and stores it as strings. Resolution to hook class instances happens at job execution time in `ConversationRunner` — not at boot — so there is no loading-order risk.

**Files:**
- Modify: `lib/daan/agent.rb`
- Modify: `lib/daan/agent_loader.rb`
- Modify or create: `test/lib/daan/agent_loader_test.rb`

- [ ] **Step 1: Check whether `test/lib/daan/agent_loader_test.rb` already exists**

```bash
ls test/lib/daan/
```

If the file exists, add the two tests below to the existing class. If not, create it with the standard header first:

```ruby
# test/lib/daan/agent_loader_test.rb
require "test_helper"

class Daan::AgentLoaderTest < ActiveSupport::TestCase
end
```

- [ ] **Step 2: Write the failing tests**

```ruby
test "parses hooks from frontmatter" do
  Dir.mktmpdir do |dir|
    path = File.join(dir, "shaper.md")
    File.write(path, <<~MD)
      ---
      name: shaper
      display_name: Shaper
      model: claude-haiku-4-5-20251001
      max_steps: 10
      hooks:
        - shaping
      tools: []
      delegates_to: []
      ---
      You shape.
    MD
    definition = Daan::AgentLoader.parse(path)
    assert_equal ["shaping"], definition[:hook_names]
  end
end

test "hook_names defaults to empty array when hooks not declared" do
  Dir.mktmpdir do |dir|
    path = File.join(dir, "plain.md")
    File.write(path, <<~MD)
      ---
      name: plain
      display_name: Plain
      model: claude-haiku-4-5-20251001
      max_steps: 5
      tools: []
      delegates_to: []
      ---
      Plain agent.
    MD
    definition = Daan::AgentLoader.parse(path)
    assert_equal [], definition[:hook_names]
  end
end
```

- [ ] **Step 3: Run the new tests to confirm they fail**

```bash
bin/rails test test/lib/daan/agent_loader_test.rb -n "/hook/"
```
Expected: `KeyError` or `NoMethodError` — `hook_names` key absent

- [ ] **Step 4: Add `hook_names` to `Agent` struct**

In `lib/daan/agent.rb`, add `hook_names` to the `Struct.new` arguments and its default:

```ruby
Agent = Struct.new(:name, :display_name, :model_name, :system_prompt, :max_steps,
                   :workspace, :base_tools, :delegates_to, :allowed_commands, :hook_names,
                   keyword_init: true) do
  def initialize(**)
    super
    self.base_tools       ||= []
    self.delegates_to     ||= []
    self.allowed_commands ||= []
    self.hook_names       ||= []
  end
  # ... rest unchanged
end
```

- [ ] **Step 5: Parse `hooks:` in `AgentLoader`**

In `lib/daan/agent_loader.rb`, inside `parse`, add after the `allowed_commands` line:

```ruby
hook_names = fm.fetch("hooks", [])
```

Add to the returned hash:

```ruby
hook_names: hook_names,
```

- [ ] **Step 6: Run the tests to confirm they pass**

```bash
bin/rails test test/lib/daan/agent_loader_test.rb -n "/hook/"
```
Expected: 2 tests, 0 failures

- [ ] **Step 7: Run the full suite to confirm no regressions**

```bash
bin/rails test
```
Expected: all pass

- [ ] **Step 8: Commit**

```bash
git add lib/daan/agent.rb lib/daan/agent_loader.rb test/lib/daan/agent_loader_test.rb
git commit -m "feat: add hook_names to Agent struct and AgentLoader"
```

---

## Task 4: `ConversationRunner` hook dispatch

Before calling `Chats::RunStep`, `ConversationRunner` collects `last_tool_calls` (the `ToolCall` records on the most recent assistant message), loads hooks via `Registry`, and dispatches `before_llm_call(chat:, last_tool_calls:)`.

Since `ConversationRunner` is called once per `LlmJob` execution and each job handles one LLM step, "dispatch before each LLM call" is satisfied by dispatching at the top of `call`.

**Files:**
- Modify: `lib/daan/conversation_runner.rb`
- Modify: `test/lib/daan/conversation_runner_test.rb`

- [ ] **Step 1: Write the failing tests**

Add to the existing `Daan::ConversationRunnerTest`:

```ruby
test "calls before_llm_call on agent's hooks with chat and last_tool_calls" do
  received_args = nil
  spy_hook = Class.new do
    include Daan::Core::Hook
    define_method(:before_llm_call) { |chat:, last_tool_calls:| received_args = { chat: chat, last_tool_calls: last_tool_calls } }
  end

  Daan::Core::Hook::Registry.stub(:agent_hooks, [spy_hook.new]) do
    Daan::Core::Hook::Registry.stub(:tool_hooks, []) do
      with_stub_step { Daan::ConversationRunner.call(@chat) }
    end
  end

  assert_not_nil received_args
  assert_equal @chat, received_args[:chat]
  assert_respond_to received_args[:last_tool_calls], :each
end

test "ripple-check message injected when agent has shaping hook and update_document was called" do
  @agent.hook_names = ["shaping"]

  assistant = @chat.messages.create!(role: "assistant", content: "Updating doc")
  ToolCall.create!(message: assistant, name: "update_document", tool_call_id: SecureRandom.hex(8))
  @chat.messages.create!(role: "tool", content: "Document updated",
                         tool_call_id: ToolCall.last.id)

  with_stub_step { Daan::ConversationRunner.call(@chat) }

  ripple = @chat.messages.where_content_like("%Ripple check%").first
  assert ripple, "expected ripple check message"
  assert_equal false, ripple.visible
  assert_equal "user", ripple.role
end
```

- [ ] **Step 2: Run the new tests to confirm they fail**

```bash
bin/rails test test/lib/daan/conversation_runner_test.rb -n "/hook\|ripple/"
```
Expected: failure — hooks not dispatched yet

- [ ] **Step 3: Implement hook dispatch in `ConversationRunner`**

```ruby
# lib/daan/conversation_runner.rb
module Daan
  class ConversationRunner
    def self.call(chat)
      agent = chat.agent

      chat.reload
      if already_responded?(chat)
        Rails.logger.info("[ConversationRunner] chat_id=#{chat.id} skipping — last user message already has a response")
        return
      end

      context_user_message_id = chat.messages.where(role: "user").maximum(:id)

      Chats::StartConversation.call(chat)
      Chats::PrepareWorkspace.call(agent)
      Chats::EnqueueCompaction.call(chat)
      Chats::ConfigureLlm.call(chat, agent)

      hooks = Daan::Core::Hook::Registry.agent_hooks(agent.hook_names) +
              Daan::Core::Hook::Registry.tool_hooks
      last_tool_calls = last_tool_calls_for(chat)
      hooks.each { |h| h.before_llm_call(chat: chat, last_tool_calls: last_tool_calls) }

      response = Chats::RunStep.call(chat, context_user_message_id: context_user_message_id)
      Chats::FinishOrReenqueue.call(chat, agent, response)
    end

    def self.last_tool_calls_for(chat)
      last_assistant = chat.messages.where(role: "assistant").order(:id).last
      return [] unless last_assistant
      ToolCall.where(message_id: last_assistant.id)
    end
    private_class_method :last_tool_calls_for

    def self.already_responded?(chat)
      last_user_message      = chat.messages.where(role: "user").last
      last_assistant_message = chat.messages.where(role: "assistant").last
      return false unless last_user_message && last_assistant_message
      return false if last_assistant_message.context_user_message_id.nil?
      return false unless last_assistant_message.context_user_message_id >= last_user_message.id

      !chat.messages.where(role: "tool").since_id(last_assistant_message.id).exists?
    end
    private_class_method :already_responded?
  end
end
```

- [ ] **Step 4: Run the new tests to confirm they pass**

```bash
bin/rails test test/lib/daan/conversation_runner_test.rb -n "/hook\|ripple/"
```
Expected: 2 tests, 0 failures

- [ ] **Step 5: Run the full suite**

```bash
bin/rails test
```
Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add lib/daan/conversation_runner.rb test/lib/daan/conversation_runner_test.rb
git commit -m "feat: dispatch before_llm_call hooks in ConversationRunner"
```

---

## Task 5: `ryan_singer.md` agent stub

A minimal agent definition that declares `hooks: [shaping]`. Tools will be fleshed out in the RyanSinger agent slice; this stub is sufficient to demo the hooks integration end-to-end.

**Files:**
- Create: `lib/daan/core/agents/ryan_singer.md`

- [ ] **Step 1: Create the agent file**

```markdown
---
name: ryan_singer
display_name: Ryan Singer
model: claude-sonnet-4-6
max_steps: 30
hooks:
  - Daan::Core::Shaping
delegates_to: []
tools:
  - Daan::Core::ReportBack
  - Daan::Core::CreateDocument
  - Daan::Core::UpdateDocument
  - SwarmMemory::Tools::MemoryWrite
  - SwarmMemory::Tools::MemoryRead
  - SwarmMemory::Tools::MemoryGlob
  - SwarmMemory::Tools::MemoryGrep
---
You are a product shaper. Your job is to help the human define problems clearly and explore solution shapes before any implementation begins.

You work with the Shape Up methodology: requirements (R), shapes (S), fit checks, and breadboards. Keep R to 9 or fewer top-level items. Fit checks are binary — ✅ or ❌ only.

{{include: partials/memory_tools.md}}
```

- [ ] **Step 2: Boot the app and verify the agent loads**

```bash
bin/rails runner "puts Daan::AgentRegistry.find('ryan_singer').inspect"
```
Expected: prints the agent struct including `hook_names: ["shaping"]`

- [ ] **Step 3: Run the full test suite including system tests**

```bash
bin/rails test && bin/rails test:system
```
Expected: all pass

- [ ] **Step 4: Commit**

```bash
git add lib/daan/core/agents/ryan_singer.md
git commit -m "feat: add ryan_singer agent stub with shaping hook"
```
