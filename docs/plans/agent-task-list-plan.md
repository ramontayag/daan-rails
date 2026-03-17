# Agent Task List (ChatStep) Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give agents a persistent, DB-backed checklist per chat that survives context compaction and is always visible in the system prompt.

**Architecture:** New `ChatStep` model (belongs_to :chat), two RubyLLM tools (`CreateSteps`, `UpdateStep`), system prompt injection in `ConversationRunner#configure_llm`, read-only `ChatStepListComponent` in the thread panel, Turbo Stream broadcasts from the tools.

**Tech Stack:** Rails 8.1, SQLite, Minitest, ViewComponent, Turbo Streams, RubyLLM tools

---

## File Structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `db/migrate/TIMESTAMP_create_chat_steps.rb` | Migration |
| Create | `app/models/chat_step.rb` | Model with validations |
| Create | `app/components/chat_step_list_component.rb` | ViewComponent for step list |
| Create | `app/components/chat_step_list_component.html.erb` | Template for step list |
| Modify | `app/components/thread_panel_component.html.erb:11-21` | Render step list in thread |
| Create | `lib/daan/core/create_steps.rb` | RubyLLM tool — bulk-create steps |
| Create | `lib/daan/core/update_step.rb` | RubyLLM tool — update step status |
| Modify | `lib/daan/conversation_runner.rb:54-68` | Inject steps into system prompt |
| Modify | `lib/daan/core/agents/developer.md` | Add CreateSteps, UpdateStep to tools |
| Modify | `lib/daan/core/agents/chief_of_staff.md` | Add CreateSteps, UpdateStep to tools |
| Modify | `lib/daan/core/agents/engineering_manager.md` | Add CreateSteps, UpdateStep to tools |
| Modify | `lib/daan/core/agents/agent_resource_manager.md` | Add CreateSteps, UpdateStep to tools |
| Create | `test/models/chat_step_test.rb` | Model tests |
| Create | `test/components/chat_step_list_component_test.rb` | Component test |
| Create | `test/lib/daan/core/create_steps_test.rb` | Tool tests |
| Create | `test/lib/daan/core/update_step_test.rb` | Tool tests |
| Create | `test/lib/daan/conversation_runner_step_injection_test.rb` | System prompt injection test |

---

## Chunk 1: ChatStep Model

### Task 1: Migration and Model

**Files:**
- Create: `db/migrate/TIMESTAMP_create_chat_steps.rb`
- Create: `app/models/chat_step.rb`
- Create: `test/models/chat_step_test.rb`

- [ ] **Step 1: Write the failing model test**

Create `test/models/chat_step_test.rb`:

```ruby
require "test_helper"

class ChatStepTest < ActiveSupport::TestCase
  setup do
    Daan::AgentRegistry.register(
      Daan::Agent.new(
        name: "chief_of_staff", display_name: "CoS",
        model_name: "claude-sonnet-4-20250514",
        system_prompt: "You are the CoS.", max_turns: 10
      )
    )
    @chat = Chat.create!(agent_name: "chief_of_staff")
  end

  test "belongs to chat" do
    step = ChatStep.create!(chat: @chat, title: "Clone repo", position: 1)
    assert_equal @chat, step.chat
  end

  test "title is required" do
    step = ChatStep.new(chat: @chat, position: 1)
    assert_not step.valid?
    assert_includes step.errors[:title], "can't be blank"
  end

  test "position is required" do
    step = ChatStep.new(chat: @chat, title: "Clone repo")
    assert_not step.valid?
    assert_includes step.errors[:position], "can't be blank"
  end

  test "status defaults to pending" do
    step = ChatStep.create!(chat: @chat, title: "Clone repo", position: 1)
    assert_equal "pending", step.status
  end

  test "status must be valid" do
    step = ChatStep.new(chat: @chat, title: "Clone repo", position: 1, status: "bogus")
    assert_not step.valid?
    assert_includes step.errors[:status], "is not included in the list"
  end

  test "position is unique within chat" do
    ChatStep.create!(chat: @chat, title: "Step one", position: 1)
    duplicate = ChatStep.new(chat: @chat, title: "Step two", position: 1)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:position], "has already been taken"
  end

  test "chat has_many steps ordered by position" do
    step_b = ChatStep.create!(chat: @chat, title: "Second", position: 2)
    step_a = ChatStep.create!(chat: @chat, title: "First", position: 1)
    assert_equal [step_a, step_b], @chat.chat_steps.to_a
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/chat_step_test.rb`
Expected: Failures — `ChatStep` class not found.

- [ ] **Step 3: Generate migration**

Run: `bin/rails generate migration CreateChatSteps chat:references title:string status:string position:integer`

Then edit the generated migration to add defaults, null constraints, and the unique index:

```ruby
class CreateChatSteps < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_steps do |t|
      t.references :chat, null: false, foreign_key: true
      t.string :title, null: false
      t.string :status, null: false, default: "pending"
      t.integer :position, null: false

      t.timestamps
    end

    add_index :chat_steps, [:chat_id, :position], unique: true
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 4: Create ChatStep model**

Create `app/models/chat_step.rb`:

```ruby
class ChatStep < ApplicationRecord
  STATUSES = %w[pending in_progress completed].freeze

  belongs_to :chat

  validates :title, presence: true
  validates :position, presence: true, uniqueness: { scope: :chat_id }
  validates :status, inclusion: { in: STATUSES }
end
```

- [ ] **Step 5: Add has_many to Chat**

Add to `app/models/chat.rb` after the existing `has_many :sub_chats` line:

```ruby
has_many :chat_steps, -> { order(:position) }, dependent: :destroy
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bin/rails test test/models/chat_step_test.rb`
Expected: All pass.

- [ ] **Step 7: Commit**

```bash
git add app/models/chat_step.rb app/models/chat.rb db/migrate/*_create_chat_steps.rb db/schema.rb test/models/chat_step_test.rb
git commit -m "feat: add ChatStep model for per-chat agent task list"
```

---

## Chunk 2: UI Component and Thread Integration

The component must exist before the tools (Chunks 3-4), because the tools broadcast by rendering `ChatStepListComponent`.

### Task 2: ChatStepListComponent

**Files:**
- Create: `app/components/chat_step_list_component.rb`
- Create: `app/components/chat_step_list_component.html.erb`
- Create: `test/components/chat_step_list_component_test.rb`
- Modify: `app/components/thread_panel_component.html.erb:11-21`

- [ ] **Step 1: Write the failing component test**

Create `test/components/chat_step_list_component_test.rb`:

```ruby
require "test_helper"

class ChatStepListComponentTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  setup do
    Daan::AgentRegistry.register(
      Daan::Agent.new(
        name: "developer", display_name: "Developer",
        model_name: "claude-sonnet-4-20250514",
        system_prompt: "You code.", max_turns: 10
      )
    )
    @chat = Chat.create!(agent_name: "developer")
  end

  test "renders steps as a checklist" do
    ChatStep.create!(chat: @chat, title: "Clone repo", position: 1, status: "completed")
    ChatStep.create!(chat: @chat, title: "Write tests", position: 2, status: "in_progress")
    ChatStep.create!(chat: @chat, title: "Implement", position: 3)

    render_inline(ChatStepListComponent.new(chat: @chat))

    assert_includes rendered_content, "Clone repo"
    assert_includes rendered_content, "Write tests"
    assert_includes rendered_content, "Implement"
  end

  test "renders nothing when no steps exist" do
    render_inline(ChatStepListComponent.new(chat: @chat))

    assert_equal "", rendered_content.strip
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/components/chat_step_list_component_test.rb`
Expected: Failure — `ChatStepListComponent` not found.

- [ ] **Step 3: Implement the component**

Create `app/components/chat_step_list_component.rb`:

```ruby
class ChatStepListComponent < ViewComponent::Base
  def initialize(chat:)
    @chat = chat
  end

  private

  attr_reader :chat

  def steps
    @steps ||= chat.chat_steps.to_a
  end

  def render?
    steps.any?
  end

  def status_icon(status)
    case status
    when "completed"   then "✓"
    when "in_progress" then "●"
    else                    " "
    end
  end

  def status_class(status)
    case status
    when "completed"   then "text-green-600 line-through"
    when "in_progress" then "text-blue-600 font-medium"
    else                    "text-gray-500"
    end
  end
end
```

Create `app/components/chat_step_list_component.html.erb`.

The component's outer div **must** carry `id="chat_step_list"` so that Turbo Stream `broadcast_replace_to` can target it. When the component renders (steps exist), the id is present. When it doesn't render (`render?` returns false), the thread panel provides a fallback empty div with the same id (see Step 5).

```erb
<div id="chat_step_list" class="mx-4 mb-3 rounded-lg border border-gray-200 bg-gray-50 p-3">
  <h4 class="text-xs font-semibold uppercase tracking-wide text-gray-400 mb-2">Steps</h4>
  <ol class="space-y-1 text-sm">
    <% steps.each do |step| %>
      <li class="flex items-center gap-2 <%= status_class(step.status) %>">
        <span class="w-4 text-center text-xs"><%= status_icon(step.status) %></span>
        <span><%= step.title %></span>
      </li>
    <% end %>
  </ol>
</div>
```

- [ ] **Step 4: Run component tests to verify they pass**

Run: `bin/rails test test/components/chat_step_list_component_test.rb`
Expected: All pass.

- [ ] **Step 5: Add step list to thread panel**

Modify `app/components/thread_panel_component.html.erb`. Add a fallback empty div with the Turbo target id, plus the component render, before `<div id="messages">` (after line 12):

```erb
    <% if chat.chat_steps.any? %>
      <%= render ChatStepListComponent.new(chat: chat) %>
    <% else %>
      <div id="chat_step_list"></div>
    <% end %>
```

This ensures `id="chat_step_list"` always exists in the DOM: either from the component (when steps exist) or from the empty fallback div (when no steps yet). Turbo Stream broadcasts from the tools replace whichever one is present, and the replacement carries the id because it's in the component template.

- [ ] **Step 6: Run full test suite**

Run: `bin/rails test && bin/rails test:system`
Expected: All pass.

- [ ] **Step 7: Commit**

```bash
git add app/components/chat_step_list_component.rb app/components/chat_step_list_component.html.erb test/components/chat_step_list_component_test.rb app/components/thread_panel_component.html.erb
git commit -m "feat: add ChatStepListComponent to thread panel"
```

---

## Chunk 3: CreateSteps Tool

### Task 3: CreateSteps Tool

**Files:**
- Create: `lib/daan/core/create_steps.rb`
- Create: `test/lib/daan/core/create_steps_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/lib/daan/core/create_steps_test.rb`:

```ruby
require "test_helper"

class Daan::Core::CreateStepsTest < ActiveSupport::TestCase
  setup do
    Daan::AgentRegistry.register(
      Daan::Agent.new(
        name: "developer", display_name: "Developer",
        model_name: "claude-sonnet-4-20250514",
        system_prompt: "You code.", max_turns: 10
      )
    )
    @chat = Chat.create!(agent_name: "developer")
  end

  test "creates steps with sequential positions" do
    tool = Daan::Core::CreateSteps.new(chat: @chat)
    result = tool.execute(steps: ["Clone repo", "Write tests", "Implement"])

    assert_equal 3, @chat.chat_steps.count
    steps = @chat.chat_steps.to_a
    assert_equal "Clone repo", steps[0].title
    assert_equal 1, steps[0].position
    assert_equal "pending", steps[0].status
    assert_equal "Write tests", steps[1].title
    assert_equal 2, steps[1].position
    assert_equal "Implement", steps[2].title
    assert_equal 3, steps[2].position
    assert_includes result, "Clone repo"
  end

  test "appends to existing steps" do
    ChatStep.create!(chat: @chat, title: "Existing step", position: 1)
    tool = Daan::Core::CreateSteps.new(chat: @chat)
    tool.execute(steps: ["New step"])

    assert_equal 2, @chat.chat_steps.count
    assert_equal 2, @chat.chat_steps.last.position
  end

  test "returns error for empty list" do
    tool = Daan::Core::CreateSteps.new(chat: @chat)
    result = tool.execute(steps: [])

    assert_includes result, "at least one"
    assert_equal 0, @chat.chat_steps.count
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/lib/daan/core/create_steps_test.rb`
Expected: Failures — `Daan::Core::CreateSteps` not found.

- [ ] **Step 3: Implement CreateSteps tool**

Create `lib/daan/core/create_steps.rb`:

```ruby
module Daan
  module Core
    class CreateSteps < RubyLLM::Tool
      extend ToolTimeout
      tool_timeout_seconds 10.seconds

      description "Create a checklist of steps for the current task. " \
                  "Use this at the start of a task to plan your work. " \
                  "Steps appear in your system prompt so you always see them."
      param :steps, desc: "Ordered list of step titles (array of strings)"

      def initialize(workspace: nil, chat: nil, storage: nil, agent_name: nil, allowed_commands: nil)
        @chat = chat
      end

      def execute(steps:)
        return "Provide at least one step." if steps.empty?

        max_pos = @chat.chat_steps.maximum(:position) || 0
        created = steps.each_with_index.map do |title, i|
          @chat.chat_steps.create!(title: title, position: max_pos + i + 1)
        end

        broadcast_step_list

        created.map { |s| "#{s.position}. [ ] #{s.title}" }.join("\n")
      end

      private

      def broadcast_step_list
        Turbo::StreamsChannel.broadcast_replace_to(
          "chat_#{@chat.id}",
          target: "chat_step_list",
          html: ApplicationController.render(ChatStepListComponent.new(chat: @chat.reload), layout: false)
        )
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/lib/daan/core/create_steps_test.rb`
Expected: All pass. `ChatStepListComponent` exists (created in Chunk 2). The broadcast renders the component via `ApplicationController.render` which works in test. If it raises, add to setup: `ApplicationController.stubs(:render).returns("")`.

- [ ] **Step 5: Commit**

```bash
git add lib/daan/core/create_steps.rb test/lib/daan/core/create_steps_test.rb
git commit -m "feat: add CreateSteps tool for agent task planning"
```

---

## Chunk 4: UpdateStep Tool

### Task 4: UpdateStep Tool

**Files:**
- Create: `lib/daan/core/update_step.rb`
- Create: `test/lib/daan/core/update_step_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/lib/daan/core/update_step_test.rb`:

```ruby
require "test_helper"

class Daan::Core::UpdateStepTest < ActiveSupport::TestCase
  setup do
    Daan::AgentRegistry.register(
      Daan::Agent.new(
        name: "developer", display_name: "Developer",
        model_name: "claude-sonnet-4-20250514",
        system_prompt: "You code.", max_turns: 10
      )
    )
    @chat = Chat.create!(agent_name: "developer")
    @step = ChatStep.create!(chat: @chat, title: "Clone repo", position: 1)
  end

  test "updates step status to in_progress" do
    tool = Daan::Core::UpdateStep.new(chat: @chat)
    result = tool.execute(position: 1, status: "in_progress")

    assert_equal "in_progress", @step.reload.status
    assert_includes result, "in_progress"
  end

  test "updates step status to completed" do
    tool = Daan::Core::UpdateStep.new(chat: @chat)
    tool.execute(position: 1, status: "completed")

    assert_equal "completed", @step.reload.status
  end

  test "returns error for invalid position" do
    tool = Daan::Core::UpdateStep.new(chat: @chat)
    result = tool.execute(position: 99, status: "completed")

    assert_includes result, "No step"
  end

  test "returns error for invalid status" do
    tool = Daan::Core::UpdateStep.new(chat: @chat)
    result = tool.execute(position: 1, status: "bogus")

    assert_includes result, "Invalid status"
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/lib/daan/core/update_step_test.rb`
Expected: Failures — `Daan::Core::UpdateStep` not found.

- [ ] **Step 3: Implement UpdateStep tool**

Create `lib/daan/core/update_step.rb`:

```ruby
module Daan
  module Core
    class UpdateStep < RubyLLM::Tool
      extend ToolTimeout
      tool_timeout_seconds 10.seconds

      description "Update the status of a step in your checklist. " \
                  "Use the position number shown in your system prompt."
      param :position, desc: "Position number of the step to update"
      param :status, desc: "New status: pending, in_progress, or completed"

      def initialize(workspace: nil, chat: nil, storage: nil, agent_name: nil, allowed_commands: nil)
        @chat = chat
      end

      def execute(position:, status:)
        unless ChatStep::STATUSES.include?(status)
          return "Invalid status '#{status}'. Use: #{ChatStep::STATUSES.join(", ")}"
        end

        step = @chat.chat_steps.find_by(position: position)
        return "No step at position #{position}." unless step

        step.update!(status: status)
        broadcast_step_list

        "Step #{position} (#{step.title}) → #{status}"
      end

      private

      def broadcast_step_list
        Turbo::StreamsChannel.broadcast_replace_to(
          "chat_#{@chat.id}",
          target: "chat_step_list",
          html: ApplicationController.render(ChatStepListComponent.new(chat: @chat.reload), layout: false)
        )
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/lib/daan/core/update_step_test.rb`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add lib/daan/core/update_step.rb test/lib/daan/core/update_step_test.rb
git commit -m "feat: add UpdateStep tool for agent step status tracking"
```

---

## Chunk 5: System Prompt Injection

### Task 5: Inject Steps Into System Prompt

**Files:**
- Modify: `lib/daan/conversation_runner.rb:54-68`
- Create: `test/lib/daan/conversation_runner_step_injection_test.rb`

- [ ] **Step 1: Write the failing test**

Create `test/lib/daan/conversation_runner_step_injection_test.rb`.

Uses the same `with_stub_memories` alias pattern from `test/lib/daan/conversation_runner_test.rb` to stub memory retrieval:

```ruby
require "test_helper"

class Daan::ConversationRunnerStepInjectionTest < ActiveSupport::TestCase
  setup do
    Daan::AgentRegistry.register(
      Daan::Agent.new(
        name: "developer", display_name: "Developer",
        model_name: "claude-sonnet-4-20250514",
        system_prompt: "You are a developer.", max_turns: 10
      )
    )
    @chat = Chat.create!(agent_name: "developer")
  end

  test "appends steps to system prompt when steps exist" do
    ChatStep.create!(chat: @chat, title: "Clone repo", position: 1, status: "completed")
    ChatStep.create!(chat: @chat, title: "Write tests", position: 2, status: "in_progress")
    ChatStep.create!(chat: @chat, title: "Implement", position: 3)

    with_stub_memories([]) do
      prompt = Daan::ConversationRunner.build_system_prompt(@chat, @chat.agent)

      assert_includes prompt, "You are a developer."
      assert_includes prompt, "## Your Current Steps"
      assert_includes prompt, "1. [x] Clone repo"
      assert_includes prompt, "2. [in progress] Write tests"
      assert_includes prompt, "3. [ ] Implement"
    end
  end

  test "does not append steps section when no steps exist" do
    with_stub_memories([]) do
      prompt = Daan::ConversationRunner.build_system_prompt(@chat, @chat.agent)

      assert_includes prompt, "You are a developer."
      assert_not_includes prompt, "Your Current Steps"
    end
  end

  private

  def with_stub_memories(results, &block)
    sc = Daan::ConversationRunner.singleton_class
    sc.alias_method(:__orig_retrieve_memories__, :retrieve_memories)
    sc.define_method(:retrieve_memories) { |_chat| results }
    block.call
  ensure
    sc.alias_method(:retrieve_memories, :__orig_retrieve_memories__)
    sc.remove_method(:__orig_retrieve_memories__)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/lib/daan/conversation_runner_step_injection_test.rb`
Expected: Failure — `build_system_prompt` method not found.

- [ ] **Step 3: Extract build_system_prompt and add step injection**

Modify `lib/daan/conversation_runner.rb`. Extract the system prompt building from `configure_llm` into a new public class method `build_system_prompt`, and add step injection.

Replace `configure_llm` (lines 54-69) with:

```ruby
def self.build_system_prompt(chat, agent)
  prompt = agent.system_prompt
  prompt = append_memories(prompt, chat)
  prompt = append_steps(prompt, chat)
  prompt
end

def self.configure_llm(chat, agent)
  system_prompt = build_system_prompt(chat, agent)

  chat
    .with_model(agent.model_name)
    .with_instructions(system_prompt)
    .with_tools(*agent.tools(chat: chat))
end
private_class_method :configure_llm

def self.append_memories(prompt, chat)
  memories = retrieve_memories(chat)
  return prompt unless memories.any?

  memory_lines = memories.map { |m|
    "[#{m[:metadata]["confidence"] || "?"}] [#{m[:metadata]["type"]}] #{m[:title]} (#{m[:file_path]})"
  }.join("\n")
  "#{prompt}\n\n## Relevant memories\n#{memory_lines}"
end
private_class_method :append_memories

def self.append_steps(prompt, chat)
  steps = chat.chat_steps.to_a
  return prompt unless steps.any?

  lines = steps.map do |step|
    marker = case step.status
    when "completed"   then "[x]"
    when "in_progress" then "[in progress]"
    else                    "[ ]"
    end
    "#{step.position}. #{marker} #{step.title}"
  end

  "#{prompt}\n\n## Your Current Steps\n#{lines.join("\n")}"
end
private_class_method :append_steps
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/lib/daan/conversation_runner_step_injection_test.rb`
Expected: All pass.

- [ ] **Step 5: Run full test suite**

Run: `bin/rails test && bin/rails test:system`
Expected: All pass — the refactor of `configure_llm` is behavior-preserving.

- [ ] **Step 6: Commit**

```bash
git add lib/daan/conversation_runner.rb test/lib/daan/conversation_runner_step_injection_test.rb
git commit -m "feat: inject ChatStep list into agent system prompt"
```

---

## Chunk 6: Wire Tools Into Agent Definitions

### Task 6: Add Tools to Agent Definitions

**Files:**
- Modify: `lib/daan/core/agents/developer.md`
- Modify: `lib/daan/core/agents/chief_of_staff.md`
- Modify: `lib/daan/core/agents/engineering_manager.md`
- Modify: `lib/daan/core/agents/agent_resource_manager.md`

- [ ] **Step 1: Add tools to all agent definitions**

Add `Daan::Core::CreateSteps` and `Daan::Core::UpdateStep` to the `tools:` list in each agent's frontmatter YAML.

In each of the four `.md` files, add these two lines to the `tools:` section:

```yaml
  - Daan::Core::CreateSteps
  - Daan::Core::UpdateStep
```

These are the only four agent definition files in `lib/daan/core/agents/`.

- [ ] **Step 2: Run full test suite**

Run: `bin/rails test && bin/rails test:system`
Expected: All pass — the agent loader resolves tool classes via `Object.const_get`, so the new tools just need to exist (which they do from Chunks 3-4).

- [ ] **Step 3: Commit**

```bash
git add lib/daan/core/agents/developer.md lib/daan/core/agents/chief_of_staff.md lib/daan/core/agents/engineering_manager.md lib/daan/core/agents/agent_resource_manager.md
git commit -m "feat: add CreateSteps and UpdateStep tools to all agents"
```

---

## Chunk 7: Manual Smoke Test

### Task 7: End-to-End Verification

- [ ] **Step 1: Start the dev server**

Run: `bin/dev`

- [ ] **Step 2: Open the chat UI and send a message**

Open the app in a browser. Start a chat with an agent. Send a multi-step task like "Clone the daan-rails repo, read the README, and summarize the architecture."

- [ ] **Step 3: Verify the agent creates steps**

Watch for a `create_steps` tool call in the thread. Verify the step list appears above the messages in the thread panel.

- [ ] **Step 4: Verify steps update as the agent works**

Watch for `update_step` tool calls. Verify the checklist updates in real-time (Turbo Stream broadcast).

- [ ] **Step 5: Verify system prompt contains steps**

Check the Rails logs for the system prompt being sent to the LLM. Confirm it includes the "Your Current Steps" section.
