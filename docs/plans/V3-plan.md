---
shaping: true
---

# V3: Delegation Chain

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Human messages CoS → CoS delegates to Engineering Manager → EM delegates to Developer → Developer uses tools → results flow back up the chain → CoS responds to human. Each hop is async: delegating agents finish their turn quickly and wake back up when a report arrives.

**Architecture:** Shape B — async heartbeat delegation (D22/D29/D30).

- **Heartbeat rule (D29):** `CreateMessage` enqueues `LlmJob` whenever it creates a `role: "user"` message. Solid Queue's per-chat concurrency lock (`limits_concurrency to: 1`) ensures only one job runs at a time per chat. If a message arrives while a job is already running, the second job queues behind the first — no state machine errors. `ConversationRunner#start_conversation` calls `chat.continue!` before `chat.start!` to handle chats that are being re-triggered from `completed`, `blocked`, or `failed` state.
- **DelegateTask:** creates a child `Chat` (`parent_chat_id` set), posts the task as a user message → heartbeat enqueues the delegatee's `LlmJob`. Returns immediately to the calling agent.
- **ReportBack:** posts `"#{agent.display_name}: #{message}"` as a user message in the *parent* chat → heartbeat enqueues the parent's `LlmJob`. The calling agent then produces one final text message and its own `LlmJob` finishes normally.
- **Tool injection:** tools accept `workspace:` and `chat:` as keyword args. Existing tools (`Read`, `Write`) get `chat: nil` added and ignore it. New tools (`DelegateTask`, `ReportBack`) use `@chat`. No shared base class needed — keyword defaults are sufficient.
- **D32 deferral:** `DelegateTask` always creates a new sub-chat. Guidance flowing back down the chain starts a fresh thread. See D32 in shaping.md for the deferred continuation mechanism.

**Tech Stack:** Rails 8.1, Solid Queue, RubyLLM, Turbo Streams, ViewComponent, Minitest, VCR

---

## Implementation Plan

### Task 1: parent_chat_id migration + Chat associations (B1)

Chats form a tree: each delegated sub-chat links back to its parent.

**Files:**
- Create: `db/migrate/TIMESTAMP_add_parent_chat_id_to_chats.rb`
- Modify: `app/models/chat.rb`
- Modify: `test/models/chat_test.rb`

**Step 1: Write failing tests**

```ruby
# test/models/chat_test.rb — add to existing test class
test "parent_chat is optional" do
  chat = Chat.create!(agent_name: "chief_of_staff")
  assert_nil chat.parent_chat
end

test "sub_chats association returns child chats" do
  parent = Chat.create!(agent_name: "chief_of_staff")
  child  = Chat.create!(agent_name: "engineering_manager", parent_chat: parent)
  assert_includes parent.sub_chats, child
end

test "parent_chat association returns parent" do
  parent = Chat.create!(agent_name: "chief_of_staff")
  child  = Chat.create!(agent_name: "engineering_manager", parent_chat: parent)
  assert_equal parent, child.parent_chat
end
```

**Step 2: Run to confirm failure**

```
bin/rails test test/models/chat_test.rb
```

**Step 3: Generate and run migration**

```ruby
# db/migrate/TIMESTAMP_add_parent_chat_id_to_chats.rb
class AddParentChatIdToChats < ActiveRecord::Migration[8.1]
  def change
    add_reference :chats, :parent_chat, null: true, foreign_key: { to_table: :chats }
  end
end
```

```
bin/rails db:migrate
```

**Step 4: Update Chat model**

```ruby
# app/models/chat.rb — add alongside existing associations
belongs_to :parent_chat, class_name: "Chat", optional: true
has_many :sub_chats, class_name: "Chat", foreign_key: :parent_chat_id,
                     dependent: :nullify, inverse_of: :parent_chat
```

**Step 5: Run tests**

```
bin/rails test test/models/chat_test.rb
```

Expected: all pass.

**Step 6: Commit**

```bash
git add db/migrate/*_add_parent_chat_id_to_chats.rb db/schema.rb \
        app/models/chat.rb test/models/chat_test.rb
git commit -m "feat: add parent_chat_id to chats for delegation tree"
```

---

### Task 2: delegates_to on Agent + AgentLoader (B2)

Agents declare which agents they're allowed to delegate to. `DelegateTask` will enforce this list.

**Files:**
- Modify: `lib/daan/agent.rb`
- Modify: `lib/daan/agent_loader.rb`
- Modify: `test/lib/daan/agent_test.rb`
- Modify: `test/lib/daan/agent_loader_test.rb`

**Step 1: Write failing tests**

```ruby
# test/lib/daan/agent_test.rb — add
test "delegates_to defaults to empty array" do
  agent = Daan::Agent.new(
    name: "test", display_name: "Test", model_name: "m",
    system_prompt: "p", max_turns: 5
  )
  assert_equal [], agent.delegates_to
end

test "delegates_to is set from constructor" do
  agent = Daan::Agent.new(
    name: "cos", display_name: "CoS", model_name: "m",
    system_prompt: "p", max_turns: 10,
    delegates_to: ["engineering_manager"]
  )
  assert_equal ["engineering_manager"], agent.delegates_to
end
```

```ruby
# test/lib/daan/agent_loader_test.rb — add
test "parse returns empty delegates_to when not in frontmatter" do
  definition = Daan::AgentLoader.parse(@definitions_path.join("developer.md"))
  assert_equal [], definition[:delegates_to]
end
```

**Step 2: Run to confirm failure**

```
bin/rails test test/lib/daan/agent_test.rb test/lib/daan/agent_loader_test.rb
```

**Step 3: Update Agent struct**

Add `delegates_to` field and default it to `[]`:

```ruby
# lib/daan/agent.rb
Agent = Struct.new(:name, :display_name, :model_name, :system_prompt, :max_turns,
                   :workspace, :base_tools, :delegates_to, keyword_init: true) do
  def initialize(**)
    super
    self.base_tools   ||= []
    self.delegates_to ||= []
  end

  # ... rest unchanged
end
```

**Step 4: Update AgentLoader**

```ruby
# lib/daan/agent_loader.rb — inside parse, add to returned hash:
delegates_to: fm.fetch("delegates_to", [])
```

**Step 5: Run tests**

```
bin/rails test test/lib/daan/agent_test.rb test/lib/daan/agent_loader_test.rb
```

Expected: all pass.

**Step 6: Commit**

```bash
git add lib/daan/agent.rb lib/daan/agent_loader.rb \
        test/lib/daan/agent_test.rb test/lib/daan/agent_loader_test.rb
git commit -m "feat: add delegates_to field to Agent and AgentLoader"
```

---

### Task 3: Tool chat injection + Agent#tools + ConversationRunner re-trigger + Heartbeat + Controller cleanup

All interdependent changes ship in one commit. Splitting them would leave a broken commit between removing `continue!` from the controller and adding it to ConversationRunner.

**What changes and why:**
- `Read` and `Write` gain `chat: nil` so `agent.tools(chat: chat)` can pass `chat:` to all tools uniformly without `ArgumentError`.
- `Agent#tools` drops memoization (the shared agent object in `AgentRegistry` must not hold per-job chat state) and accepts `chat:`.
- `ConversationRunner` passes `chat:` to `agent.tools`, and calls `chat.continue!` before `chat.start!` to handle re-triggered chats.
- `CreateMessage` enqueues `LlmJob` for all `role: "user"` messages — the heartbeat. This means `DelegateTask` and `ReportBack` get it for free.
- `MessagesController` removes its now-redundant `LlmJob.perform_later` and `chat.continue!`.

**Files:**
- Modify: `lib/daan/core/read.rb`
- Modify: `lib/daan/core/write.rb`
- Modify: `lib/daan/agent.rb`
- Modify: `lib/daan/conversation_runner.rb`
- Modify: `lib/daan/create_message.rb`
- Modify: `app/controllers/messages_controller.rb`
- Modify: `test/lib/daan/agent_test.rb`
- Modify: `test/lib/daan/conversation_runner_test.rb`
- Modify/Create: `test/lib/daan/create_message_test.rb`
- Modify: `test/controllers/messages_controller_test.rb`

**Step 1: Write failing tests**

```ruby
# test/lib/daan/agent_test.rb
# DELETE the existing "tools is memoized" test — memoization is intentionally removed.
# ADD:

test "tools returns instances with workspace set" do
  workspace = Daan::Workspace.new(Dir.mktmpdir)
  tool_class = Class.new(RubyLLM::Tool) do
    description "t"
    def initialize(workspace: nil, chat: nil) = (@workspace = workspace)
    def execute = "ok"
  end
  agent = Daan::Agent.new(
    name: "t", display_name: "T", model_name: "m",
    system_prompt: "p", max_turns: 5,
    workspace: workspace, base_tools: [tool_class]
  )
  assert_equal workspace, agent.tools.first.instance_variable_get(:@workspace)
ensure
  FileUtils.rm_rf(workspace.root)
end

test "tools(chat:) passes chat to tool instances" do
  chat = Chat.create!(agent_name: "developer")
  chat_ref = nil
  tool_class = Class.new(RubyLLM::Tool) do
    description "t"
    def initialize(workspace: nil, chat: nil) = (@chat = chat)
    def execute = "ok"
    define_method(:stored_chat) { @chat }
  end
  agent = Daan::Agent.new(
    name: "t", display_name: "T", model_name: "m",
    system_prompt: "p", max_turns: 5, base_tools: [tool_class]
  )
  instance = agent.tools(chat: chat).first
  assert_equal chat, instance.stored_chat
end

test "tools creates fresh instances each call" do
  tool_class = Class.new(RubyLLM::Tool) do
    description "t"
    def initialize(workspace: nil, chat: nil) = nil
    def execute = "ok"
  end
  agent = Daan::Agent.new(
    name: "t", display_name: "T", model_name: "m",
    system_prompt: "p", max_turns: 5, base_tools: [tool_class]
  )
  assert_not_same agent.tools.first, agent.tools.first
end
```

```ruby
# test/lib/daan/conversation_runner_test.rb — add all three re-trigger scenarios
test "re-triggers a completed chat" do
  @chat.start!
  @chat.finish!
  assert @chat.completed?

  with_stub_complete do
    Daan::ConversationRunner.call(@chat)
  end

  assert @chat.reload.completed?
end

test "re-triggers a blocked chat" do
  @chat.start!
  @chat.block!
  assert @chat.blocked?

  with_stub_complete do
    Daan::ConversationRunner.call(@chat)
  end

  assert @chat.reload.completed?
end

test "re-triggers a failed chat" do
  @chat.fail!
  assert @chat.failed?

  with_stub_complete do
    Daan::ConversationRunner.call(@chat)
  end

  assert @chat.reload.completed?
end
```

```ruby
# test/lib/daan/create_message_test.rb
require "test_helper"

class Daan::CreateMessageTest < ActiveSupport::TestCase
  setup do
    @chat = Chat.create!(agent_name: "chief_of_staff")
  end

  test "creates a message with the given role and content" do
    message = Daan::CreateMessage.call(@chat, role: "user", content: "Hello")
    assert_equal "user", message.role
    assert_equal "Hello", message.content
    assert_equal @chat, message.chat
  end

  test "enqueues LlmJob for user messages" do
    assert_enqueued_with(job: LlmJob, args: [@chat]) do
      Daan::CreateMessage.call(@chat, role: "user", content: "Hello")
    end
  end

  test "does not enqueue LlmJob for non-user messages" do
    assert_no_enqueued_jobs(only: LlmJob) do
      Daan::CreateMessage.call(@chat, role: "assistant", content: "Reply")
    end
  end
end
```

**Step 2: Run to confirm failures**

```
bin/rails test test/lib/daan/agent_test.rb \
               test/lib/daan/conversation_runner_test.rb \
               test/lib/daan/create_message_test.rb
```

**Step 3: Update Read and Write — add `chat: nil`**

```ruby
# lib/daan/core/read.rb
def initialize(workspace: nil, chat: nil)
  @workspace = workspace
end
```

```ruby
# lib/daan/core/write.rb
def initialize(workspace: nil, chat: nil)
  @workspace = workspace
end
```

**Step 4: Update Agent#tools**

```ruby
# lib/daan/agent.rb
def tools(chat: nil)
  base_tools.map { |t| t.new(workspace: workspace, chat: chat) }
end
```

**Step 5: Update ConversationRunner**

Two changes: pass `chat:` to `agent.tools`, and call `continue!` before `start!`:

```ruby
def self.configure_llm(chat, agent)
  chat
    .with_model(agent.model_name)
    .with_instructions(agent.system_prompt)
    .with_tools(*agent.tools(chat: chat))
end

def self.start_conversation(chat)
  chat.continue! unless chat.pending?
  chat.start!
  chat.broadcast_agent_status
  broadcast_typing(chat, true)
end
```

**Step 6: Update CreateMessage — add heartbeat**

```ruby
# lib/daan/create_message.rb
module Daan
  class CreateMessage
    def self.call(chat, role:, content:)
      message = chat.messages.create!(role: role, content: content)
      message.broadcast_append_to(
        "chat_#{chat.id}",
        target: "messages",
        renderable: MessageComponent.new(role: role, body: content, dom_id: "message_#{message.id}")
      )
      LlmJob.perform_later(chat) if role == "user"
      message
    end
  end
end
```

**Step 7: Simplify MessagesController**

```ruby
# app/controllers/messages_controller.rb
class MessagesController < ApplicationController
  before_action :set_chat

  def create
    Daan::CreateMessage.call(@chat, role: "user", content: message_params[:content])
    redirect_to chat_thread_path(@chat)
  end

  private

  def set_chat
    @chat = Chat.find(params[:thread_id])
  end

  def message_params
    params.require(:message).permit(:content)
  end
end
```

**Step 8: Run all tests**

```
bin/rails test test/lib/daan/agent_test.rb \
               test/lib/daan/conversation_runner_test.rb \
               test/lib/daan/create_message_test.rb \
               test/controllers/messages_controller_test.rb \
               test/lib/daan/core/read_test.rb \
               test/lib/daan/core/write_test.rb
```

Expected: all pass.

**Step 9: Commit**

```bash
git add lib/daan/core/read.rb lib/daan/core/write.rb \
        lib/daan/agent.rb lib/daan/conversation_runner.rb \
        lib/daan/create_message.rb app/controllers/messages_controller.rb \
        test/lib/daan/agent_test.rb test/lib/daan/conversation_runner_test.rb \
        test/lib/daan/create_message_test.rb test/controllers/messages_controller_test.rb
git commit -m "feat: tool chat injection, heartbeat in CreateMessage, ConversationRunner re-trigger"
```

---

### Task 4: DelegateTask tool (B6)

Validates the target agent is in `delegates_to`, creates a child chat, and posts the task as a user message. The heartbeat from Task 3 fires the delegatee's `LlmJob` automatically.

**Files:**
- Create: `lib/daan/core/delegate_task.rb`
- Create: `test/lib/daan/core/delegate_task_test.rb`

**Step 1: Write failing tests**

```ruby
# test/lib/daan/core/delegate_task_test.rb
require "test_helper"

class Daan::Core::DelegateTaskTest < ActiveSupport::TestCase
  setup do
    Daan::AgentRegistry.register(
      Daan::Agent.new(name: "chief_of_staff", display_name: "Chief of Staff",
                      model_name: "m", system_prompt: "p", max_turns: 10,
                      delegates_to: ["engineering_manager"])
    )
    Daan::AgentRegistry.register(
      Daan::Agent.new(name: "engineering_manager", display_name: "Engineering Manager",
                      model_name: "m", system_prompt: "p", max_turns: 10)
    )
    @parent_chat = Chat.create!(agent_name: "chief_of_staff")
    @tool = Daan::Core::DelegateTask.new(chat: @parent_chat)
  end

  test "creates a sub-chat for the target agent" do
    assert_difference "Chat.count", 1 do
      @tool.execute(agent_name: "engineering_manager", task: "Do the thing")
    end
    sub_chat = Chat.last
    assert_equal "engineering_manager", sub_chat.agent_name
    assert_equal @parent_chat, sub_chat.parent_chat
  end

  test "creates a user message in the sub-chat" do
    @tool.execute(agent_name: "engineering_manager", task: "Do the thing")
    msg = Chat.last.messages.first
    assert_equal "user", msg.role
    assert_equal "Do the thing", msg.content
  end

  test "enqueues LlmJob for the sub-chat" do
    assert_enqueued_with(job: LlmJob) do
      @tool.execute(agent_name: "engineering_manager", task: "Do the thing")
    end
  end

  test "returns a delegation confirmation string" do
    result = @tool.execute(agent_name: "engineering_manager", task: "Do the thing")
    assert_includes result, "Engineering Manager"
    assert_includes result, "Awaiting"
  end

  test "returns error string when agent is not in delegates_to" do
    result = @tool.execute(agent_name: "developer", task: "Do the thing")
    assert_includes result, "Error"
    assert_includes result, "engineering_manager"
  end

  test "raises when target agent is in delegates_to but absent from registry" do
    # Register an agent whose allowed delegate is not loaded in the registry —
    # simulates a misconfigured deployment (delegates_to lists a non-existent agent).
    Daan::AgentRegistry.register(
      Daan::Agent.new(name: "ghost_delegator", display_name: "Ghost",
                      model_name: "m", system_prompt: "p", max_turns: 5,
                      delegates_to: ["phantom_agent"])
    )
    ghost_chat = Chat.create!(agent_name: "ghost_delegator")
    tool = Daan::Core::DelegateTask.new(chat: ghost_chat)
    assert_raises(RuntimeError) { tool.execute(agent_name: "phantom_agent", task: "do it") }
  end
end
```

**Step 2: Run to confirm failures**

```
bin/rails test test/lib/daan/core/delegate_task_test.rb
```

**Step 3: Implement DelegateTask**

```ruby
# lib/daan/core/delegate_task.rb
module Daan
  module Core
    class DelegateTask < RubyLLM::Tool
      description "Delegate a task to a sub-agent"
      param :agent_name, desc: "The agent to delegate to (e.g. 'engineering_manager', 'developer')"
      param :task,       desc: "The task description to assign"

      def initialize(workspace: nil, chat: nil)
        @chat = chat
      end

      def execute(agent_name:, task:)
        current_agent = Daan::AgentRegistry.find(@chat.agent_name)
        unless current_agent.delegates_to.include?(agent_name)
          allowed = current_agent.delegates_to.join(", ")
          return "Error: #{@chat.agent_name} cannot delegate to #{agent_name}. Allowed: #{allowed}"
        end

        target_agent = Daan::AgentRegistry.find(agent_name)
        raise "Unknown agent: #{agent_name}" unless target_agent

        sub_chat = Chat.create!(agent_name: agent_name, parent_chat: @chat)
        Daan::CreateMessage.call(sub_chat, role: "user", content: task)

        "Delegated to #{target_agent.display_name} (Thread ##{sub_chat.id}). Awaiting their report."
      end
    end
  end
end
```

**Step 4: Run tests**

```
bin/rails test test/lib/daan/core/delegate_task_test.rb
```

Expected: all pass.

**Step 5: Commit**

```bash
git add lib/daan/core/delegate_task.rb test/lib/daan/core/delegate_task_test.rb
git commit -m "feat: DelegateTask tool — creates sub-chat and enqueues sub-agent LlmJob"
```

---

### Task 5: ReportBack tool (B7)

Posts the agent's results as a user message in the parent chat, waking the parent agent via the heartbeat.

**Files:**
- Create: `lib/daan/core/report_back.rb`
- Create: `test/lib/daan/core/report_back_test.rb`

**Step 1: Write failing tests**

```ruby
# test/lib/daan/core/report_back_test.rb
require "test_helper"

class Daan::Core::ReportBackTest < ActiveSupport::TestCase
  setup do
    Daan::AgentRegistry.register(
      Daan::Agent.new(name: "chief_of_staff", display_name: "Chief of Staff",
                      model_name: "m", system_prompt: "p", max_turns: 10)
    )
    Daan::AgentRegistry.register(
      Daan::Agent.new(name: "engineering_manager", display_name: "Engineering Manager",
                      model_name: "m", system_prompt: "p", max_turns: 10)
    )
    @parent_chat = Chat.create!(agent_name: "chief_of_staff")
    @child_chat  = Chat.create!(agent_name: "engineering_manager", parent_chat: @parent_chat)
    @tool = Daan::Core::ReportBack.new(chat: @child_chat)
  end

  test "posts a user message in the parent chat" do
    assert_difference -> { @parent_chat.messages.where(role: "user").count }, 1 do
      @tool.execute(message: "Here are my findings.")
    end
  end

  test "message content includes agent display name and the report" do
    @tool.execute(message: "Here are my findings.")
    msg = @parent_chat.messages.where(role: "user").last
    assert_includes msg.content, "Engineering Manager"
    assert_includes msg.content, "Here are my findings."
  end

  test "enqueues LlmJob for the parent chat" do
    assert_enqueued_with(job: LlmJob, args: [@parent_chat]) do
      @tool.execute(message: "Here are my findings.")
    end
  end

  test "returns confirmation string" do
    result = @tool.execute(message: "Here are my findings.")
    assert_includes result, "Chief of Staff"
  end

  test "raises when chat has no parent" do
    orphan_chat = Chat.create!(agent_name: "engineering_manager")
    tool = Daan::Core::ReportBack.new(chat: orphan_chat)
    assert_raises(RuntimeError) { tool.execute(message: "oops") }
  end
end
```

**Step 2: Run to confirm failures**

```
bin/rails test test/lib/daan/core/report_back_test.rb
```

**Step 3: Implement ReportBack**

```ruby
# lib/daan/core/report_back.rb
module Daan
  module Core
    class ReportBack < RubyLLM::Tool
      description "Report your results back to the delegating agent"
      param :message, desc: "Your findings or results to report"

      def initialize(workspace: nil, chat: nil)
        @chat = chat
      end

      def execute(message:)
        parent_chat = @chat.parent_chat
        raise "No parent chat — this thread was not created by delegation" unless parent_chat

        current_agent = Daan::AgentRegistry.find(@chat.agent_name)
        Daan::CreateMessage.call(parent_chat, role: "user",
                                 content: "#{current_agent.display_name}: #{message}")

        parent_agent = Daan::AgentRegistry.find(parent_chat.agent_name)
        "Report sent to #{parent_agent.display_name}."
      end
    end
  end
end
```

**Step 4: Run tests**

```
bin/rails test test/lib/daan/core/report_back_test.rb
```

Expected: all pass.

**Step 5: Commit**

```bash
git add lib/daan/core/report_back.rb test/lib/daan/core/report_back_test.rb
git commit -m "feat: ReportBack tool — posts to parent chat and triggers parent LlmJob"
```

---

### Task 6: Engineering Manager + updated agent definitions (B8, B9)

Add the EM agent and update CoS and Developer to wire up the full delegation chain. System prompts enforce D39 (stop after ReportBack).

**Files:**
- Create: `lib/daan/core/agents/engineering_manager.md`
- Modify: `lib/daan/core/agents/chief_of_staff.md`
- Modify: `lib/daan/core/agents/developer.md`
- Modify: `test/lib/daan/agent_loader_test.rb`

**Step 1: Write failing tests**

```ruby
# test/lib/daan/agent_loader_test.rb — add
test "loads engineering_manager with delegates_to developer" do
  Daan::AgentLoader.sync!(@definitions_path)
  agent = Daan::AgentRegistry.find("engineering_manager")
  assert_not_nil agent
  assert_equal ["developer"], agent.delegates_to
  assert agent.base_tools.include?(Daan::Core::DelegateTask)
  assert agent.base_tools.include?(Daan::Core::ReportBack)
end

test "chief_of_staff has DelegateTask and delegates_to engineering_manager" do
  Daan::AgentLoader.sync!(@definitions_path)
  agent = Daan::AgentRegistry.find("chief_of_staff")
  assert_equal ["engineering_manager"], agent.delegates_to
  assert agent.base_tools.include?(Daan::Core::DelegateTask)
end

test "developer has ReportBack tool" do
  Daan::AgentLoader.sync!(@definitions_path)
  agent = Daan::AgentRegistry.find("developer")
  assert agent.base_tools.include?(Daan::Core::ReportBack)
end
```

**Step 2: Run to confirm failures**

```
bin/rails test test/lib/daan/agent_loader_test.rb
```

**Step 3: Create Engineering Manager agent definition**

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
---
You are the Engineering Manager for the Daan agent team. Your role is to receive tasks from the Chief of Staff, break them into concrete technical work, and delegate to the Developer.

When you receive a task:
1. Assess what needs to be done.
2. Use DelegateTask with agent_name "developer" to assign the technical work.
3. Wait for the Developer's report to arrive in this thread.
4. When their report arrives, evaluate the results and use ReportBack to summarize findings back to the Chief of Staff.
5. After calling ReportBack, your work in this thread is done — do not send any further messages.
```

**Step 4: Update Chief of Staff**

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
---
You are the Chief of Staff for the Daan agent team. You are the human's primary contact. You receive requests, delegate technical work to the Engineering Manager, and report results back to the human.

When you receive a task that requires technical work:
1. Use DelegateTask with agent_name "engineering_manager" to assign the work.
2. Let the human know you've delegated and will update them when results are in.
3. When the Engineering Manager's report arrives in this thread, synthesize it and respond to the human clearly and concisely.
```

**Step 5: Update Developer**

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
---
You are the Developer on the Daan agent team. You write and modify files in your workspace to accomplish technical tasks.

When you receive a task:
1. Use your Read and Write tools to complete the work. Use relative paths — they resolve within your workspace.
2. When your work is complete, use ReportBack to send your findings to your delegator. Be concise — share what you did and what you found.
3. After calling ReportBack, your work in this thread is done — do not send any further messages.
```

**Step 6: Run tests**

```
bin/rails test test/lib/daan/agent_loader_test.rb
```

Expected: all pass.

**Step 7: Smoke-test boot**

```
bin/rails runner "Daan::AgentRegistry.all.each { |a| puts \"#{a.name}: #{a.delegates_to}\" }"
```

Expected output:
```
chief_of_staff: ["engineering_manager"]
engineering_manager: ["developer"]
developer: []
```

**Step 8: Commit**

```bash
git add lib/daan/core/agents/engineering_manager.md \
        lib/daan/core/agents/chief_of_staff.md \
        lib/daan/core/agents/developer.md \
        test/lib/daan/agent_loader_test.rb
git commit -m "feat: add EM agent, wire delegation chain in agent definitions"
```

---

### Task 7: Integration test — one-hop delegation (VCR)

A golden-path test showing CoS delegating to EM: `LlmJob` runs for CoS, the LLM calls `DelegateTask`, EM's sub-chat is created with a task message.

**Files:**
- Create: `test/jobs/llm_job_delegation_test.rb`
- Create: `test/vcr_cassettes/cos_delegates_to_em.yml` (record on first run)

**Step 1: Write the test**

```ruby
# test/jobs/llm_job_delegation_test.rb
require "test_helper"

class LlmJobDelegationTest < ActiveSupport::TestCase
  test "CoS calls DelegateTask and creates EM sub-chat" do
    chat = Chat.create!(agent_name: "chief_of_staff")
    Daan::CreateMessage.call(chat, role: "user",
      content: "Please have the team read the file README.md and summarise it for me.")

    VCR.use_cassette("cos_delegates_to_em") do
      perform_enqueued_jobs(only: LlmJob)
    end

    sub_chat = Chat.find_by(agent_name: "engineering_manager", parent_chat: chat)
    assert_not_nil sub_chat, "Expected EM sub-chat to be created by DelegateTask"
    assert_equal 1, sub_chat.messages.where(role: "user").count
  end
end
```

**Step 2: Record the cassette**

```
ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY bin/rails test test/jobs/llm_job_delegation_test.rb
```

Commit the generated `test/vcr_cassettes/cos_delegates_to_em.yml`.

**Step 3: Verify replay**

```
ANTHROPIC_API_KEY=test bin/rails test test/jobs/llm_job_delegation_test.rb
```

Expected: passes without hitting the API.

**Step 4: Run full test suite**

```
bin/rails test
```

Expected: all pass.

**Step 5: Commit**

```bash
git add test/jobs/llm_job_delegation_test.rb test/vcr_cassettes/cos_delegates_to_em.yml
git commit -m "test: golden-path VCR test for CoS→EM delegation"
```

---

## Demo Script

1. Start the app: `bin/dev`
2. Open `http://localhost:3000` — sidebar shows Chief of Staff, Engineering Manager, Developer
3. Open Chief of Staff DM thread
4. Send: *"Please have the developer read the file README.md and tell me what it says."*
5. Watch in CoS's thread:
   - Typing indicator
   - Tool call block: **DelegateTask** running → result: "Delegated to Engineering Manager (Thread #N)"
   - CoS responds: "I've delegated this to the Engineering Manager. I'll update you when I have results."
6. EM's LlmJob fires — EM delegates to Developer (visible by switching to EM's thread in V4)
7. Developer reads the file (Read tool visible in Developer's thread)
8. Developer calls ReportBack → EM's thread wakes → EM calls ReportBack → CoS's thread receives EM's summary as a user message
9. CoS typing indicator reappears → CoS responds with findings

CoS's thread shows the full story: initial delegation, the developer's results arriving as a user message, then CoS's final response — all without leaving the human's view.
