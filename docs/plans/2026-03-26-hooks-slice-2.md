# Hooks Slice 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the full hook lifecycle (`before_conversation`, `before_tool_call`, `after_tool_call`, `after_conversation`) to `ConversationRunner` and introduce a tool-scoped `AuditLogHook` that logs Bash and Write calls to demonstrate the end-to-end.

**Architecture:** Lifecycle no-ops are added to `Hook::InstanceMethods`. `before_conversation` fires in `ConversationRunner` when `chat.step_count == 0` (first LLM step of a turn). `before_tool_call`/`after_tool_call` are dispatched via a new `Daan::Core::HookDispatch` module prepended on each tool instance; it reads active hooks from `Thread.current[:daan_active_hooks]`, which `ConversationRunner` sets around `RunStep.call`. `HookDispatch` captures the keyword args passed to `execute` and forwards them as `args:` to hook methods. `after_conversation` fires after `FinishOrReenqueue` when the chat reaches a terminal state, and also on RunStep failure. `Daan::Core::Hooks::AuditLog` is a tool hook that registers itself on load via `include Daan::Core::Hook.module(applies_to: [Daan::Core::Bash, Daan::Core::Write])` — no boot-time directory scanning needed; Zeitwerk eager-loads all `lib/` on boot because `config.autoload_lib` adds `lib/` to `eager_load_paths`.

**Tech Stack:** Rails 8.1, Minitest, `Thread.current` thread-locals, `Daan::Core::Hook` module, `Daan::Agent#tools`.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `lib/daan/core/hook.rb` | Add 4 lifecycle method no-ops to `InstanceMethods` |
| Modify | `test/lib/daan/core/hook_test.rb` | Cover new lifecycle methods |
| Modify | `lib/daan/conversation_runner.rb` | `before_conversation` dispatch; thread-local setup/teardown around `RunStep`; `after_conversation` dispatch |
| Create | `lib/daan/core/hook_dispatch.rb` | `Daan::Core::HookDispatch` — prepended on tool instances; dispatches `before_tool_call`/`after_tool_call` from thread-local |
| Modify | `lib/daan/agent.rb` | Also prepend `HookDispatch` on tool instances alongside `SafeExecute` |
| Create | `lib/daan/core/hooks/audit_log.rb` | `Daan::Core::Hooks::AuditLog` tool hook for Bash — logs before/after |
| Create | `test/lib/daan/core/hook_dispatch_test.rb` | Unit tests for `HookDispatch` |
| Create | `test/lib/daan/core/hooks/audit_log_test.rb` | Tests for `AuditLogHook` |
| Modify | `test/lib/daan/conversation_runner_test.rb` | Tests for `before_conversation`, thread-local, and `after_conversation` lifecycle |

---

## Task 0: Lifecycle method no-ops in `Daan::Core::Hook::InstanceMethods`

`Hook::InstanceMethods` currently only has `before_llm_call` and `applies_to_tool?`. Add four more no-ops. Hook classes override only what they need.

**Files:**
- Modify: `lib/daan/core/hook.rb`
- Modify: `test/lib/daan/core/hook_test.rb`

- [ ] **Step 1: Write the failing tests**

Add to `test/lib/daan/core/hook_test.rb` inside `Daan::Core::HookTest`:

```ruby
test "included class gets default no-op before_conversation" do
  klass = Class.new { include Daan::Core::Hook }
  assert_nothing_raised { klass.new.before_conversation(chat: nil) }
end

test "included class gets default no-op before_tool_call" do
  klass = Class.new { include Daan::Core::Hook }
  assert_nothing_raised { klass.new.before_tool_call(chat: nil, tool_name: "foo", args: {}) }
end

test "included class gets default no-op after_tool_call" do
  klass = Class.new { include Daan::Core::Hook }
  assert_nothing_raised { klass.new.after_tool_call(chat: nil, tool_name: "foo", result: "ok", args: {}) }
end

test "included class gets default no-op after_conversation" do
  klass = Class.new { include Daan::Core::Hook }
  assert_nothing_raised { klass.new.after_conversation(chat: nil, status: :completed) }
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/lib/daan/core/hook_test.rb -n "/no-op before_conversation|no-op before_tool_call|no-op after_tool_call|no-op after_conversation/"
```

Expected: `ArgumentError` or `NoMethodError` — methods not defined yet.

- [ ] **Step 3: Add the four no-ops to `Hook::InstanceMethods`**

In `lib/daan/core/hook.rb`, add inside `module InstanceMethods` after `before_llm_call`:

```ruby
def before_conversation(chat:); end
def before_tool_call(chat:, tool_name:, args:); end
def after_tool_call(chat:, tool_name:, args:, result:); end
def after_conversation(chat:, status:); end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
bin/rails test test/lib/daan/core/hook_test.rb
```

Expected: all pass, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/daan/core/hook.rb test/lib/daan/core/hook_test.rb
git commit -m "feat: add before_conversation, before/after_tool_call, after_conversation no-ops to Hook"
```

---

## Task 1: `before_conversation` in `ConversationRunner`

Fire `before_conversation(chat:)` on all hooks when `chat.step_count == 0` — meaning this is the first LLM step for the current conversation turn (no assistant messages yet since the last visible user message). This does NOT fire on tool-call re-enqueue steps (step 2, 3, …).

**Files:**
- Modify: `lib/daan/conversation_runner.rb`
- Modify: `test/lib/daan/conversation_runner_test.rb`

- [ ] **Step 1: Write the failing tests**

Add to `test/lib/daan/conversation_runner_test.rb` after the last existing `before_llm_call` test. Also add `teardown { Daan::Core::Hook::Registry.clear }` to the class (check if one already exists — if not, add it):

```ruby
teardown { Daan::Core::Hook::Registry.clear }

test "dispatches before_conversation when step_count is 0 (first LLM step)" do
  received = nil
  spy = Class.new do
    include Daan::Core::Hook
    define_method(:before_conversation) { |chat:| received = chat }
  end

  Daan::Core::Hook::Registry.stub(:agent_hooks, [spy.new]) do
    Daan::Core::Hook::Registry.stub(:tool_hooks, []) do
      with_stub_step { Daan::ConversationRunner.call(@chat) }
    end
  end

  assert_equal @chat, received
end

test "does not dispatch before_conversation on subsequent steps (step_count > 0)" do
  prior_steps(1)  # creates one assistant message after the user message → step_count = 1
  called = false
  spy = Class.new do
    include Daan::Core::Hook
    define_method(:before_conversation) { |chat:| called = true }
  end

  Daan::Core::Hook::Registry.stub(:agent_hooks, [spy.new]) do
    Daan::Core::Hook::Registry.stub(:tool_hooks, []) do
      with_stub_step { Daan::ConversationRunner.call(@chat) }
    end
  end

  assert_not called, "before_conversation must not fire on step 2+"
end
```

- [ ] **Step 2: Run the new tests to confirm they fail**

```bash
bin/rails test test/lib/daan/conversation_runner_test.rb -n "/before_conversation/"
```

Expected: failures — `before_conversation` not dispatched yet.

- [ ] **Step 3: Add `before_conversation` dispatch to `ConversationRunner`**

In `lib/daan/conversation_runner.rb`, after the hooks are assembled and `last_tool_calls` are collected, add the `before_conversation` dispatch block:

```ruby
hooks = Daan::Core::Hook::Registry.agent_hooks(agent.hook_names) +
        Daan::Core::Hook::Registry.tool_hooks
last_tool_calls = last_tool_calls_for(chat)
hooks.each { |h| h.before_llm_call(chat: chat, last_tool_calls: last_tool_calls) rescue Rails.logger.error("[Hook] #{h.class} raised during before_llm_call: #{$!.message}") }

if chat.step_count == 0
  hooks.each do |h|
    h.before_conversation(chat: chat)
  rescue => e
    Rails.logger.error("[Hook] #{h.class} raised during before_conversation: #{e.message}")
  end
end
```

- [ ] **Step 4: Run the new tests to confirm they pass**

```bash
bin/rails test test/lib/daan/conversation_runner_test.rb -n "/before_conversation/"
```

Expected: 2 tests, 0 failures.

- [ ] **Step 5: Run the full suite to confirm no regressions**

```bash
bin/rails test
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add lib/daan/conversation_runner.rb test/lib/daan/conversation_runner_test.rb
git commit -m "feat: dispatch before_conversation hook on first LLM step"
```

---

## Task 2: `Daan::Core::HookDispatch` — `before_tool_call` / `after_tool_call`

Tool calls happen inside `chat.step` (RubyLLM internals). We hook in by prepending `HookDispatch` on each tool instance. It wraps `execute(...)` — calling `super` to invoke `SafeExecute#execute` (and ultimately the tool) while dispatching hooks before and after. Active hooks are passed via `Thread.current[:daan_active_hooks]`; `ConversationRunner` sets this before `RunStep.call` and clears it in `ensure`.

Method lookup chain after prepend: `HookDispatch#execute` → `SafeExecute#execute` → `BashTool#execute`.

All our tools have `self.name` (RubyLLM instance method returning the tool name), so `HookDispatch` uses `self.name` for `applies_to_tool?` without depending on `Daan::Core::Tool::ClassMethods`.

**Files:**
- Create: `lib/daan/core/hook_dispatch.rb`
- Modify: `lib/daan/agent.rb`
- Modify: `lib/daan/conversation_runner.rb`
- Create: `test/lib/daan/core/hook_dispatch_test.rb`
- Modify: `test/lib/daan/conversation_runner_test.rb`

- [ ] **Step 1: Write the `HookDispatch` unit tests**

Create `test/lib/daan/core/hook_dispatch_test.rb`:

```ruby
# test/lib/daan/core/hook_dispatch_test.rb
require "test_helper"

class Daan::Core::HookDispatchTest < ActiveSupport::TestCase
  # A minimal fake tool: just returns its input as a string.
  class FakeTool
    def name; "fake_tool"; end
    def execute(**kwargs)
      "result:#{kwargs.inspect}"
    end
  end

  setup do
    @fake_tool = FakeTool.new
    @fake_tool.singleton_class.prepend(Daan::Core::HookDispatch)
    @chat = Chat.create!(agent_name: "test_agent").tap do
      Daan::AgentRegistry.register(
        Daan::Agent.new(name: "test_agent", display_name: "T", model_name: "m",
                        system_prompt: "s", max_steps: 1)
      )
    end
  end

  teardown { Thread.current[:daan_active_hooks] = nil }

  test "calls execute normally when no thread-local hooks set" do
    result = @fake_tool.execute(foo: "bar")
    assert_equal "result:{foo: \"bar\"}", result
  end

  test "dispatches before_tool_call to applicable hooks with args" do
    received = nil
    hook = hook_for("fake_tool") { |chat:, tool_name:, args:| received = { chat: chat, tool_name: tool_name, args: args } }
    with_active_hooks([hook]) { @fake_tool.execute(foo: "bar") }
    assert_not_nil received
    assert_equal "fake_tool", received[:tool_name]
    assert_equal @chat, received[:chat]
    assert_equal({ foo: "bar" }, received[:args])
  end

  test "dispatches after_tool_call to applicable hooks with result and args" do
    received = nil
    hook = after_hook_for("fake_tool") { |chat:, tool_name:, args:, result:| received = { result: result, args: args } }
    with_active_hooks([hook]) { @fake_tool.execute(foo: "bar") }
    assert_equal "result:{foo: \"bar\"}", received[:result]
    assert_equal({ foo: "bar" }, received[:args])
  end

  test "does not dispatch to hooks that don't apply to this tool" do
    called = false
    hook = hook_for("other_tool") { |**| called = true }
    with_active_hooks([hook]) { @fake_tool.execute }
    assert_not called
  end

  test "a hook that raises during before_tool_call does not abort execution" do
    boom = hook_for("fake_tool") { |**| raise "before boom" }
    result = nil
    with_active_hooks([boom]) { result = @fake_tool.execute(x: 1) }
    assert_equal "result:{x: 1}", result
  end

  test "a hook that raises during after_tool_call does not abort execution" do
    boom = after_hook_for("fake_tool") { |**| raise "after boom" }
    result = nil
    with_active_hooks([boom]) { result = @fake_tool.execute(x: 1) }
    assert_equal "result:{x: 1}", result
  end

  private

  # Build a spy hook whose applies_to_tool? returns true for `tool_name`
  # and whose before_tool_call calls the given block.
  def hook_for(tool_name, &blk)
    tn = tool_name
    Class.new do
      def applies_to_tool?(name); name == @tool_name; end
      define_method(:initialize) { @tool_name = tn }
      define_method(:before_tool_call, &blk)
      def after_tool_call(chat:, tool_name:, args:, result:); end
    end.new
  end

  def after_hook_for(tool_name, &blk)
    tn = tool_name
    Class.new do
      def applies_to_tool?(name); name == @tool_name; end
      define_method(:initialize) { @tool_name = tn }
      def before_tool_call(chat:, tool_name:, args:); end
      define_method(:after_tool_call, &blk)
    end.new
  end

  def with_active_hooks(hooks)
    Thread.current[:daan_active_hooks] = { hooks: hooks, chat: @chat }
    yield
  ensure
    Thread.current[:daan_active_hooks] = nil
  end
end
```

- [ ] **Step 2: Run the new tests to confirm they fail**

```bash
bin/rails test test/lib/daan/core/hook_dispatch_test.rb
```

Expected: `NameError: uninitialized constant Daan::Core::HookDispatch`

- [ ] **Step 3: Implement `Daan::Core::HookDispatch`**

Create `lib/daan/core/hook_dispatch.rb`:

```ruby
# lib/daan/core/hook_dispatch.rb
module Daan
  module Core
    module HookDispatch
      # Uses explicit **kwargs (not ...) so we can pass args: to hooks.
      # timeout_seconds is consumed by SafeExecute and not part of the tool's
      # own args, so we exclude it when forwarding to hooks.
      def execute(timeout_seconds: nil, **kwargs)
        active = Thread.current[:daan_active_hooks]
        if active
          tool_name = self.name
          active[:hooks].each do |h|
            next unless h.applies_to_tool?(tool_name)
            h.before_tool_call(chat: active[:chat], tool_name: tool_name, args: kwargs)
          rescue => e
            Rails.logger.error("[Hook] #{h.class} raised during before_tool_call: #{e.message}")
          end
        end

        result = super(timeout_seconds: timeout_seconds, **kwargs)

        if active
          tool_name = self.name
          active[:hooks].each do |h|
            next unless h.applies_to_tool?(tool_name)
            h.after_tool_call(chat: active[:chat], tool_name: tool_name, args: kwargs, result: result)
          rescue => e
            Rails.logger.error("[Hook] #{h.class} raised during after_tool_call: #{e.message}")
          end
        end

        result
      end
    end
  end
end
```

- [ ] **Step 4: Run the `HookDispatch` tests to confirm they pass**

```bash
bin/rails test test/lib/daan/core/hook_dispatch_test.rb
```

Expected: 6 tests, 0 failures.

- [ ] **Step 5: Prepend `HookDispatch` on tool instances in `Agent#tools`**

In `lib/daan/agent.rb`, inside the `tools` method, add the `HookDispatch` prepend after `SafeExecute`:

```ruby
def tools(chat: nil)
  all_kwargs = { workspace: workspace, chat: chat, storage: Daan::Memory.storage,
                 agent_name: name, allowed_commands: allowed_commands }
  base_tools.map do |t|
    accepted = t.instance_method(:initialize).parameters.map(&:last)
    t.new(**all_kwargs.slice(*accepted)).tap do |instance|
      instance.singleton_class.prepend(Core::SafeExecute)
      instance.singleton_class.prepend(Core::HookDispatch)
    end
  end
end
```

The prepend order matters: `HookDispatch` is prepended last, so it is first in the method lookup chain (`HookDispatch#execute` → `SafeExecute#execute` → `ToolClass#execute`).

- [ ] **Step 6: Set and clear the thread-local in `ConversationRunner` around `RunStep`**

In `lib/daan/conversation_runner.rb`, replace:

```ruby
response = Chats::RunStep.call(chat, context_user_message_id: context_user_message_id)
Chats::FinishOrReenqueue.call(chat, agent, response)
```

with:

```ruby
Thread.current[:daan_active_hooks] = { hooks: hooks, chat: chat }
begin
  response = Chats::RunStep.call(chat, context_user_message_id: context_user_message_id)
ensure
  Thread.current[:daan_active_hooks] = nil
end
Chats::FinishOrReenqueue.call(chat, agent, response)
```

- [ ] **Step 7: Write a ConversationRunner test that verifies the thread-local is set during RunStep**

Add to `test/lib/daan/conversation_runner_test.rb`:

```ruby
test "sets Thread.current[:daan_active_hooks] during RunStep execution" do
  captured = nil
  # Replace RunStep.call so we can inspect thread state mid-execution
  Daan::Chats::RunStep.stub(:call, ->(chat, **) {
    captured = Thread.current[:daan_active_hooks]
    OpenStruct.new("tool_call?" => false, role: "assistant")
  }) do
    Daan::ConversationRunner.call(@chat)
  end
  assert_not_nil captured, "expected [:daan_active_hooks] to be set during RunStep"
  assert_respond_to captured[:hooks], :each
  assert_equal @chat, captured[:chat]
end

test "clears Thread.current[:daan_active_hooks] after RunStep" do
  Daan::Chats::RunStep.stub(:call, ->(*) {
    OpenStruct.new("tool_call?" => false, role: "assistant")
  }) do
    Daan::ConversationRunner.call(@chat)
  end
  assert_nil Thread.current[:daan_active_hooks]
end

test "clears Thread.current[:daan_active_hooks] even when RunStep raises" do
  Daan::Chats::RunStep.stub(:call, ->(*) { raise RuntimeError, "boom" }) do
    assert_raises(RuntimeError) { Daan::ConversationRunner.call(@chat) }
  end
  assert_nil Thread.current[:daan_active_hooks]
end
```

- [ ] **Step 8: Run new ConversationRunner tests**

```bash
bin/rails test test/lib/daan/conversation_runner_test.rb -n "/thread/"
```

Expected: 3 tests, 0 failures.

- [ ] **Step 9: Run the full suite**

```bash
bin/rails test
```

Expected: all pass.

- [ ] **Step 10: Commit**

```bash
git add lib/daan/core/hook_dispatch.rb lib/daan/agent.rb lib/daan/conversation_runner.rb \
  test/lib/daan/core/hook_dispatch_test.rb test/lib/daan/conversation_runner_test.rb
git commit -m "feat: add HookDispatch for before/after_tool_call via thread-local"
```

---

## Task 3: `after_conversation` in `ConversationRunner`

Dispatch `after_conversation(chat:, status:)` when the chat reaches a terminal state. Status is one of `:completed`, `:blocked`, `:failed`.

- **Completed / Blocked:** detected after `FinishOrReenqueue.call` via `terminal_status_for(chat.reload)`. When `FinishOrReenqueue` re-enqueues (tool call, not at max steps), the chat is still `in_progress` → `terminal_status_for` returns `nil` → no dispatch.
- **Failed:** `RunStep.call` raises (after already calling `chat.fail!` internally) → rescue in `ConversationRunner` → dispatch `:failed` → re-raise.

**Files:**
- Modify: `lib/daan/conversation_runner.rb`
- Modify: `test/lib/daan/conversation_runner_test.rb`

- [ ] **Step 1: Write the failing tests**

Add to `test/lib/daan/conversation_runner_test.rb`:

```ruby
test "dispatches after_conversation(:completed) when chat finishes" do
  received = nil
  spy = Class.new do
    include Daan::Core::Hook
    define_method(:after_conversation) { |chat:, status:| received = { chat: chat, status: status } }
  end

  Daan::Core::Hook::Registry.stub(:agent_hooks, [spy.new]) do
    Daan::Core::Hook::Registry.stub(:tool_hooks, []) do
      with_stub_step { Daan::ConversationRunner.call(@chat) }
    end
  end

  assert_not_nil received
  assert_equal :completed, received[:status]
end

test "dispatches after_conversation(:blocked) when max steps reached" do
  received_status = nil
  spy = Class.new do
    include Daan::Core::Hook
    define_method(:after_conversation) { |chat:, status:| received_status = status }
  end

  prior_steps(@agent.max_steps - 1)

  Daan::Core::Hook::Registry.stub(:agent_hooks, [spy.new]) do
    Daan::Core::Hook::Registry.stub(:tool_hooks, []) do
      with_stub_tool_step { Daan::ConversationRunner.call(@chat) }
    end
  end

  assert_equal :blocked, received_status
end

test "dispatches after_conversation(:failed) when RunStep raises" do
  received_status = nil
  spy = Class.new do
    include Daan::Core::Hook
    define_method(:after_conversation) { |chat:, status:| received_status = status }
  end

  Daan::Core::Hook::Registry.stub(:agent_hooks, [spy.new]) do
    Daan::Core::Hook::Registry.stub(:tool_hooks, []) do
      with_stub_step(raise_error: RuntimeError.new("LLM down")) do
        assert_raises(RuntimeError) { Daan::ConversationRunner.call(@chat) }
      end
    end
  end

  assert_equal :failed, received_status
end

test "does not dispatch after_conversation when chat is re-enqueued mid-conversation" do
  called = false
  spy = Class.new do
    include Daan::Core::Hook
    define_method(:after_conversation) { |chat:, status:| called = true }
  end

  # Tool call step, max_steps NOT reached — LlmJob re-enqueued, chat stays in_progress
  Daan::Core::Hook::Registry.stub(:agent_hooks, [spy.new]) do
    Daan::Core::Hook::Registry.stub(:tool_hooks, []) do
      with_stub_tool_step { Daan::ConversationRunner.call(@chat) }
    end
  end

  assert_not called, "after_conversation must not fire when LlmJob is re-enqueued"
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/lib/daan/conversation_runner_test.rb -n "/after_conversation/"
```

Expected: failures — `after_conversation` not dispatched yet.

- [ ] **Step 3: Add `after_conversation` dispatch to `ConversationRunner`**

In `lib/daan/conversation_runner.rb`, add the following private class method at the bottom:

```ruby
def self.terminal_status_for(chat)
  return :completed if chat.completed?
  return :blocked   if chat.blocked?
  return :failed    if chat.failed?
  nil
end
private_class_method :terminal_status_for

def self.dispatch_after_conversation(hooks, chat, status)
  return unless status
  hooks.each do |h|
    h.after_conversation(chat: chat, status: status)
  rescue => e
    Rails.logger.error("[Hook] #{h.class} raised during after_conversation: #{e.message}")
  end
end
private_class_method :dispatch_after_conversation
```

Then update the RunStep section in `call` to add failure rescue and terminal dispatch:

```ruby
Thread.current[:daan_active_hooks] = { hooks: hooks, chat: chat }
begin
  response = Chats::RunStep.call(chat, context_user_message_id: context_user_message_id)
rescue => e
  dispatch_after_conversation(hooks, chat, :failed)
  raise
ensure
  Thread.current[:daan_active_hooks] = nil
end
Chats::FinishOrReenqueue.call(chat, agent, response)
dispatch_after_conversation(hooks, chat, terminal_status_for(chat.reload))
```

- [ ] **Step 4: Run the `after_conversation` tests**

```bash
bin/rails test test/lib/daan/conversation_runner_test.rb -n "/after_conversation/"
```

Expected: 4 tests, 0 failures.

- [ ] **Step 5: Run the full suite**

```bash
bin/rails test
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add lib/daan/conversation_runner.rb test/lib/daan/conversation_runner_test.rb
git commit -m "feat: dispatch after_conversation hook on terminal chat state"
```

---

## Task 4: `Daan::Core::Hooks::AuditLog`

A real tool hook demonstrating the end-to-end. Registered via `include Daan::Core::Hook.module(applies_to: [Daan::Core::Bash])` — auto-registers in `Hook::Registry` on load. Since `config.autoload_lib` in `application.rb` adds all of `lib/` to `eager_load_paths`, this file is loaded (and the hook registered) on application boot in all environments.

**Files:**
- Create: `lib/daan/core/hooks/audit_log.rb`
- Create: `test/lib/daan/core/hooks/audit_log_test.rb`

- [ ] **Step 1: Write the tests**

Create `test/lib/daan/core/hooks/audit_log_test.rb`:

```ruby
# test/lib/daan/core/hooks/audit_log_test.rb
require "test_helper"

class Daan::Core::Hooks::AuditLogTest < ActiveSupport::TestCase
  setup do
    @hook = Daan::Core::Hooks::AuditLog.new
    @chat = Chat.create!(agent_name: "test_agent").tap do
      Daan::AgentRegistry.register(
        Daan::Agent.new(name: "test_agent", display_name: "T", model_name: "m",
                        system_prompt: "s", max_steps: 1)
      )
    end
  end

  teardown { Daan::Core::Hook::Registry.clear }

  test "applies to Bash tool" do
    assert @hook.applies_to_tool?(Daan::Core::Bash.tool_name)
  end

  test "applies to Write tool" do
    assert @hook.applies_to_tool?(Daan::Core::Write.tool_name)
  end

  test "does not apply to other tools" do
    refute @hook.applies_to_tool?(Daan::Core::Read.tool_name)
  end

  test "before_tool_call logs an info message containing chat_id and tool_name" do
    logged = []
    Rails.logger.stub(:info, ->(msg) { logged << msg }) do
      @hook.before_tool_call(chat: @chat, tool_name: "bash", args: { commands: [["ls"]] })
    end
    assert logged.any? { |m| m.include?("bash") && m.include?(@chat.id.to_s) },
           "expected log message with tool name and chat_id, got: #{logged.inspect}"
  end

  test "after_tool_call logs an info message containing chat_id, tool_name, and truncated result" do
    logged = []
    result = "a" * 200  # longer than the truncation limit
    Rails.logger.stub(:info, ->(msg) { logged << msg }) do
      @hook.after_tool_call(chat: @chat, tool_name: "bash", args: {}, result: result)
    end
    assert logged.any? { |m| m.include?("bash") && m.include?(@chat.id.to_s) },
           "expected log message with tool name and chat_id, got: #{logged.inspect}"
  end

  test "is registered in Hook::Registry after file is loaded" do
    # Loading the constant triggers autoload — then it should appear in registry
    Daan::Core::Hooks::AuditLog  # ensure loaded
    assert_includes Daan::Core::Hook::Registry.all, Daan::Core::Hooks::AuditLog
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bin/rails test test/lib/daan/core/hooks/audit_log_test.rb
```

Expected: `NameError: uninitialized constant Daan::Core::Hooks::AuditLog`

- [ ] **Step 3: Create the `AuditLog` hook**

Create `lib/daan/core/hooks/audit_log.rb`:

```ruby
# lib/daan/core/hooks/audit_log.rb
module Daan
  module Core
    module Hooks
      class AuditLog
        include Daan::Core::Hook.module(applies_to: [Daan::Core::Bash, Daan::Core::Write])

        def before_tool_call(chat:, tool_name:, args:)
          Rails.logger.info("[AuditLog] before_tool_call chat_id=#{chat.id} tool=#{tool_name}")
        end

        def after_tool_call(chat:, tool_name:, args:, result:)
          preview = result.to_s.truncate(120)
          Rails.logger.info("[AuditLog] after_tool_call chat_id=#{chat.id} tool=#{tool_name} result=#{preview}")
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run the tests to confirm they pass**

```bash
bin/rails test test/lib/daan/core/hooks/audit_log_test.rb
```

Expected: 6 tests, 0 failures.

- [ ] **Step 5: Run the full suite including system tests**

```bash
bin/rails test && bin/rails test:system
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add lib/daan/core/hooks/audit_log.rb test/lib/daan/core/hooks/audit_log_test.rb
git commit -m "feat: add AuditLogHook for Bash tool calls (demo of tool hook auto-discovery)"
```
