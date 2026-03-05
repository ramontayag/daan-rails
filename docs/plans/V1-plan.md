---
shaping: true
---

# V1: Human Chats With One Agent — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Human sends a message to the Chief of Staff agent and receives an LLM response in a Slack-like chat UI.

**Architecture:** Agents are plain Ruby value objects (`Daan::Agent`) loaded from frontmatter Markdown files into an in-memory `Daan::AgentRegistry` — no `agents` DB table. RubyLLM persists conversations via `acts_as_chat`/`acts_as_message` on `Chat`/`Message`. `Chat` stores `agent_name:string` to identify its agent; `chat.agent` looks up the registry. Agent status (idle/busy) is derived from `Chat.task_status` — no status column anywhere. Solid Queue drives the job chain with per-chat concurrency. Turbo Streams push updates live. Tailwind CSS + ViewComponents + Lookbook for the UI.

**Tech Stack:** Rails 8.1, SQLite, RubyLLM, Solid Queue, Turbo Streams, Tailwind CSS, ViewComponent, Lookbook

**Key types:**
- `Daan::Agent` — plain Ruby struct. In-memory. Loaded from MD files.
- `Daan::AgentRegistry` — in-memory hash keyed by agent name. Lives for the process lifetime.
- `Chat` — ActiveRecord + `acts_as_chat`. Stores `agent_name`, `task_status`, `turn_count`. Chat = thread = task (D19).
- `Message` — ActiveRecord + `acts_as_message`.

---

## Task 1: Add Gems

**Files:**
- Modify: `Gemfile`

**Step 1: Add gems**

```ruby
gem "ruby_llm"
gem "tailwindcss-rails", "~> 4.0"
gem "view_component"

group :development do
  gem "lookbook"
end
```

**Step 2: Bundle install**

Run: `bundle install`
Expected: All gems install successfully.

**Step 3: Install Tailwind**

Run: `bin/rails tailwindcss:install`
Expected: Creates `app/assets/tailwind/application.css`, updates layout, adds build task.

**Step 4: Install RubyLLM**

Run: `bin/rails generate ruby_llm:install --skip-active-storage`
Expected: Creates migrations for `chats`, `messages`, `tool_calls`, `models` tables. Creates model files. Creates `config/initializers/ruby_llm.rb`.

**Step 5: Install Lookbook**

Run: `bin/rails generate lookbook:install`
Expected: Mounts Lookbook at `/rails/lookbook` in development.

**Step 6: Inspect the generated Chat migration**

Open the generated `db/migrate/*_create_chats.rb`. Note the exact column name RubyLLM uses for the model identifier (likely `model_id` or similar). You will use this name in every `Chat.create!(...)` call throughout the plan. Write it down here: `_________`.

**Step 7: Run migrations**

Run: `bin/rails db:migrate`
Expected: Tables created successfully.

**Step 8: Commit**

```bash
git add -A
git commit -m "build: add ruby_llm, tailwindcss-rails, view_component, lookbook gems"
```

---

## Task 2: Daan::Agent + AgentRegistry

Plain Ruby value objects. No migrations, no AR.

**Files:**
- Create: `lib/daan/agent.rb`
- Create: `lib/daan/agent_registry.rb`
- Create: `test/lib/daan/agent_test.rb`
- Create: `test/lib/daan/agent_registry_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/lib/daan/agent_test.rb
require "test_helper"

class Daan::AgentTest < ActiveSupport::TestCase
  setup do
    @agent = Daan::Agent.new(
      name: "chief_of_staff",
      display_name: "Chief of Staff",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You are the Chief of Staff.",
      max_turns: 10
    )
  end

  test "has expected attributes" do
    assert_equal "chief_of_staff", @agent.name
    assert_equal "Chief of Staff", @agent.display_name
    assert_equal "claude-sonnet-4-20250514", @agent.model_name
    assert_equal 10, @agent.max_turns
  end

  test "to_param returns name for URL routing" do
    assert_equal "chief_of_staff", @agent.to_param
  end

  test "busy? is false when no in-progress chats" do
    assert_not @agent.busy?
  end

  test "busy? is true when agent has an in-progress chat" do
    Chat.create!(agent_name: "chief_of_staff", model_id: "claude-sonnet-4-20250514",
                 task_status: "in_progress")
    assert @agent.busy?
  end

  test "max_turns_reached? at the limit" do
    assert @agent.max_turns_reached?(10)
    assert_not @agent.max_turns_reached?(9)
  end
end
```

Note: replace `model_id:` with the column name you noted in Task 1 Step 6.

```ruby
# test/lib/daan/agent_registry_test.rb
require "test_helper"

class Daan::AgentRegistryTest < ActiveSupport::TestCase
  setup do
    Daan::AgentRegistry.clear
    @agent = Daan::Agent.new(name: "chief_of_staff", display_name: "CoS",
                             model_name: "m", system_prompt: "p", max_turns: 10)
  end

  teardown { Daan::AgentRegistry.clear }

  test "registers and finds an agent by name" do
    Daan::AgentRegistry.register(@agent)
    assert_equal @agent, Daan::AgentRegistry.find("chief_of_staff")
  end

  test "all returns all registered agents" do
    Daan::AgentRegistry.register(@agent)
    assert_includes Daan::AgentRegistry.all, @agent
  end

  test "find raises KeyError for unknown agent" do
    assert_raises(KeyError) { Daan::AgentRegistry.find("nobody") }
  end

  test "clear removes all agents" do
    Daan::AgentRegistry.register(@agent)
    Daan::AgentRegistry.clear
    assert_raises(KeyError) { Daan::AgentRegistry.find("chief_of_staff") }
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/lib/daan/`
Expected: FAIL — `NameError: uninitialized constant Daan::Agent`

**Step 3: Implement**

```ruby
# lib/daan/agent.rb
module Daan
  Agent = Struct.new(:name, :display_name, :model_name, :system_prompt, :max_turns,
                     keyword_init: true) do
    def to_param
      name
    end

    def busy?
      Chat.exists?(agent_name: name, task_status: "in_progress")
    end

    def max_turns_reached?(turn_count)
      turn_count >= max_turns
    end
  end
end
```

```ruby
# lib/daan/agent_registry.rb
module Daan
  class AgentRegistry
    @registry = {}

    class << self
      def register(agent)
        @registry[agent.name] = agent
      end

      def find(name)
        @registry.fetch(name) { raise KeyError, "No agent registered: #{name.inspect}" }
      end

      def all
        @registry.values
      end

      def clear
        @registry = {}
      end
    end
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/lib/daan/`
Expected: All 8 tests PASS.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: Daan::Agent plain Ruby struct and AgentRegistry"
```

---

## Task 3: Extend Chat with Agent Name and Task State

RubyLLM's generator created the `Chat` model. We add `agent_name`, `task_status`, and `turn_count`.

**Files:**
- Create: `test/models/chat_test.rb`
- Create: `db/migrate/TIMESTAMP_add_agent_name_and_task_fields_to_chats.rb`
- Modify: `app/models/chat.rb`
- Create: `test/fixtures/chats.yml`

**Step 1: Write the failing test**

```ruby
# test/models/chat_test.rb
require "test_helper"

class ChatTest < ActiveSupport::TestCase
  setup do
    Daan::AgentRegistry.clear
    @agent = Daan::Agent.new(name: "chief_of_staff", display_name: "CoS",
                             model_name: "claude-sonnet-4-20250514",
                             system_prompt: "You are CoS.", max_turns: 10)
    Daan::AgentRegistry.register(@agent)
  end

  teardown { Daan::AgentRegistry.clear }

  test "agent returns the registered Daan::Agent" do
    chat = Chat.new(agent_name: "chief_of_staff")
    assert_equal @agent, chat.agent
  end

  test "task_status defaults to pending" do
    chat = Chat.new
    assert_equal "pending", chat.task_status
  end

  test "task_status must be a valid state" do
    chat = chats(:hello_cos)
    chat.task_status = "dancing"
    assert_not chat.valid?
  end

  test "turn_count defaults to 0" do
    assert_equal 0, Chat.new.turn_count
  end

  test "max_turns_reached? delegates to agent" do
    chat = chats(:hello_cos)
    chat.turn_count = @agent.max_turns
    assert chat.max_turns_reached?
  end

  test "raises KeyError for unknown agent_name" do
    chat = Chat.new(agent_name: "ghost")
    assert_raises(KeyError) { chat.agent }
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/chat_test.rb`
Expected: FAIL — missing columns.

**Step 3: Generate migration**

Run: `bin/rails generate migration AddAgentNameAndTaskFieldsToChats`

Edit the generated migration:

```ruby
class AddAgentNameAndTaskFieldsToChats < ActiveRecord::Migration[8.1]
  def change
    add_column :chats, :agent_name, :string, null: false
    add_column :chats, :task_status, :string, null: false, default: "pending"
    add_column :chats, :turn_count, :integer, null: false, default: 0
    add_index :chats, :agent_name
  end
end
```

**Step 4: Run migration**

Run: `bin/rails db:migrate`

**Step 5: Update Chat model**

```ruby
# app/models/chat.rb
class Chat < ApplicationRecord
  acts_as_chat

  validates :agent_name, presence: true
  validates :task_status, presence: true,
    inclusion: { in: %w[pending in_progress completed failed blocked] }

  def agent
    Daan::AgentRegistry.find(agent_name)
  end

  def max_turns_reached?
    agent.max_turns_reached?(turn_count)
  end
end
```

**Step 6: Create fixtures**

```yaml
# test/fixtures/chats.yml
hello_cos:
  agent_name: chief_of_staff
  task_status: pending
  turn_count: 0
  model_id: claude-sonnet-4-20250514
```

Replace `model_id` with the column name from Task 1 Step 6.

**Step 7: Run tests to verify they pass**

Run: `bin/rails test test/models/chat_test.rb`
Expected: All 6 tests PASS.

**Step 8: Commit**

```bash
git add -A
git commit -m "feat: Chat with agent_name and task state"
```

---

## Task 4: Agent Definition Loader

Reads frontmatter Markdown files and populates `AgentRegistry`. No DB writes.

**Files:**
- Create: `lib/daan/agent_loader.rb`
- Create: `lib/daan/core/agents/chief_of_staff.md`
- Create: `test/lib/daan/agent_loader_test.rb`

**Step 1: Create the agent definition file**

```markdown
---
name: chief_of_staff
display_name: Chief of Staff
model: claude-sonnet-4-20250514
max_turns: 10
---

You are the Chief of Staff for the Daan agent team.

You are the primary point of contact for the human user. When the human asks
you to do something, you assess the request and handle it directly.

Be concise, helpful, and proactive. Ask clarifying questions when the request
is ambiguous.
```

**Step 2: Write the failing test**

```ruby
# test/lib/daan/agent_loader_test.rb
require "test_helper"

class Daan::AgentLoaderTest < ActiveSupport::TestCase
  setup do
    Daan::AgentRegistry.clear
    @definitions_path = Rails.root.join("lib/daan/core/agents")
  end

  teardown { Daan::AgentRegistry.clear }

  test "parse returns a hash with agent attributes" do
    definition = Daan::AgentLoader.parse(@definitions_path.join("chief_of_staff.md"))

    assert_equal "chief_of_staff", definition[:name]
    assert_equal "Chief of Staff", definition[:display_name]
    assert_equal "claude-sonnet-4-20250514", definition[:model_name]
    assert_equal 10, definition[:max_turns]
    assert_includes definition[:system_prompt], "Chief of Staff"
  end

  test "sync! registers a Daan::Agent for each definition file" do
    Daan::AgentLoader.sync!(@definitions_path)

    agent = Daan::AgentRegistry.find("chief_of_staff")
    assert_instance_of Daan::Agent, agent
    assert_equal "Chief of Staff", agent.display_name
    assert_equal "claude-sonnet-4-20250514", agent.model_name
  end

  test "sync! re-running overwrites previous registration" do
    Daan::AgentLoader.sync!(@definitions_path)
    Daan::AgentLoader.sync!(@definitions_path)
    assert_equal 1, Daan::AgentRegistry.all.length
  end
end
```

**Step 3: Run test to verify it fails**

Run: `bin/rails test test/lib/daan/agent_loader_test.rb`
Expected: FAIL — `NameError: uninitialized constant Daan::AgentLoader`

**Step 4: Implement AgentLoader**

```ruby
# lib/daan/agent_loader.rb
require "yaml"

module Daan
  class AgentLoader
    FRONTMATTER_REGEX = /\A---\s*\n(.*?\n?)---\s*\n(.*)\z/m

    def self.parse(file_path)
      content = File.read(file_path)
      match = content.match(FRONTMATTER_REGEX)
      raise "Invalid agent definition: #{file_path}" unless match

      frontmatter = YAML.safe_load(match[1])
      body = match[2].strip

      {
        name: frontmatter.fetch("name"),
        display_name: frontmatter.fetch("display_name"),
        model_name: frontmatter.fetch("model"),
        max_turns: frontmatter.fetch("max_turns"),
        system_prompt: body
      }
    end

    def self.sync!(directory)
      Dir.glob(Pathname(directory).join("*.md")).each do |file_path|
        definition = parse(file_path)
        AgentRegistry.register(Agent.new(**definition))
      end
    end
  end
end
```

**Step 5: Run tests to verify they pass**

Run: `bin/rails test test/lib/daan/agent_loader_test.rb`
Expected: All 3 tests PASS.

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: agent definition loader — populates AgentRegistry from MD files"
```

---

## Task 5: LlmJob — The Agentic Loop

Load all messages as context, call RubyLLM, save the response, update task state.

**Files:**
- Create: `test/jobs/llm_job_test.rb`
- Create: `app/jobs/llm_job.rb`

**Architecture note:** The controller saves the user message immediately (for instant Turbo display). When LlmJob runs, that message is already in `chat.messages`. We must NOT call `chat.ask(content)` — that would add the user message a second time. Instead, we build the full history from all saved messages and call RubyLLM's completion API without adding a new user message.

**Verify during implementation:** After `rails generate ruby_llm:install`, read the generated `Chat` model to find the method `acts_as_chat` adds for "send these messages as context and get a completion." It may be `chat.complete(messages:)`, or you may need to call `RubyLLM.chat(messages: history).with_model(...).with_instructions(...)`. The stub target in the tests below is `chat` (stubbing `chat.complete`) — adjust the stub and implementation together if the API differs.

**Step 1: Write the failing tests**

```ruby
# test/jobs/llm_job_test.rb
require "test_helper"

FakeResponse = Struct.new(:content)

class LlmJobTest < ActiveSupport::TestCase
  setup do
    Daan::AgentRegistry.clear
    @agent = Daan::Agent.new(
      name: "test_agent", display_name: "Test Agent",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You are a test agent.",
      max_turns: 3
    )
    Daan::AgentRegistry.register(@agent)
    @chat = Chat.create!(agent_name: "test_agent", model_id: "claude-sonnet-4-20250514")
    @chat.messages.create!(role: "user", content: "Hello agent")
  end

  teardown { Daan::AgentRegistry.clear }

  test "saves an assistant message" do
    stub_llm(@chat, "Hello human!") { LlmJob.perform_now(@chat) }

    assert_equal 2, @chat.messages.count
    assert_equal "assistant", @chat.messages.last.role
    assert_equal "Hello human!", @chat.messages.last.content
  end

  test "passes full conversation history to LLM" do
    @chat.messages.create!(role: "assistant", content: "Hi")
    @chat.messages.create!(role: "user", content: "Follow-up")

    captured = nil
    @chat.stub(:complete, ->(messages:, **) { captured = messages; FakeResponse.new("ok") }) do
      LlmJob.perform_now(@chat)
    end

    assert_equal 3, captured.length
    assert_equal "Hello agent", captured.first[:content]
  end

  test "increments turn_count" do
    stub_llm(@chat, "Hi") { LlmJob.perform_now(@chat) }
    assert_equal 1, @chat.reload.turn_count
  end

  test "sets task_status to completed" do
    stub_llm(@chat, "Done") { LlmJob.perform_now(@chat) }
    assert_equal "completed", @chat.reload.task_status
  end

  test "sets task_status to blocked when max_turns reached" do
    @chat.update!(turn_count: @agent.max_turns - 1)
    stub_llm(@chat, "Last turn") { LlmJob.perform_now(@chat) }
    assert_equal "blocked", @chat.reload.task_status
  end

  test "sets task_status to failed and reraises on exception" do
    @chat.stub(:complete, ->(**) { raise "LLM down" }) do
      assert_raises(RuntimeError) { LlmJob.perform_now(@chat) }
    end
    assert_equal "failed", @chat.reload.task_status
  end

  private

  def stub_llm(chat, content)
    chat.stub(:complete, ->(**) { FakeResponse.new(content) }) { yield }
  end
end
```

Replace `model_id:` with the column name from Task 1 Step 6.

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/jobs/llm_job_test.rb`
Expected: FAIL — `NameError: uninitialized constant LlmJob`

**Step 3: Implement LlmJob**

```ruby
# app/jobs/llm_job.rb
class LlmJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: ->(chat) { "chat_#{chat.id}" }

  def perform(chat)
    agent = chat.agent
    chat.update!(task_status: "in_progress")

    # Build full history from all saved messages. We do NOT call chat.ask() here
    # because the user message was already saved by the controller.
    messages = chat.messages.order(:created_at).map do |m|
      { role: m.role, content: m.content }
    end

    # Verify the exact method signature from acts_as_chat after running the generator.
    # If chat.complete doesn't exist, use:
    #   RubyLLM.chat(messages: messages)
    #     .with_model(agent.model_name)
    #     .with_instructions(agent.system_prompt)
    #     .complete (or equivalent)
    response = chat.complete(
      messages: messages,
      model: agent.model_name,
      instructions: agent.system_prompt
    )

    chat.messages.create!(role: "assistant", content: response.content)
    chat.increment!(:turn_count)

    if agent.max_turns_reached?(chat.turn_count)
      chat.update!(task_status: "blocked")
    else
      chat.update!(task_status: "completed")
    end
  rescue => e
    chat.update!(task_status: "failed")
    raise
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/jobs/llm_job_test.rb`
Expected: All 6 tests PASS. Adjust the stub target and implementation together if the actual RubyLLM API differs — both must match.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: LlmJob with full conversation history and turn counting"
```

---

## Task 6: Heartbeat — Auto-Enqueue LlmJob on New User Message

Any new user message enqueues an LlmJob. Solid Queue's `limits_concurrency` deduplicates — if a job is already running for this chat, the new one queues behind it (D22/D29).

**Files:**
- Create: `test/models/message_test.rb`
- Modify: `app/models/message.rb`

**Step 1: Write the failing test**

```ruby
# test/models/message_test.rb
require "test_helper"

class MessageTest < ActiveSupport::TestCase
  setup do
    Daan::AgentRegistry.clear
    Daan::AgentRegistry.register(Daan::Agent.new(
      name: "test_agent", display_name: "TA",
      model_name: "m", system_prompt: "p", max_turns: 10
    ))
    @chat = Chat.create!(agent_name: "test_agent", model_id: "m")
  end

  teardown { Daan::AgentRegistry.clear }

  test "enqueues LlmJob when human sends a message" do
    assert_enqueued_with(job: LlmJob) do
      @chat.messages.create!(role: "user", content: "Hello")
    end
  end

  test "does not enqueue LlmJob for assistant messages" do
    assert_no_enqueued_jobs(only: LlmJob) do
      @chat.messages.create!(role: "assistant", content: "Hi back")
    end
  end

  test "enqueues LlmJob even when chat is in_progress — Solid Queue deduplicates" do
    @chat.update!(task_status: "in_progress")
    assert_enqueued_with(job: LlmJob) do
      @chat.messages.create!(role: "user", content: "Follow-up while busy")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/message_test.rb`
Expected: FAIL — no job enqueued.

**Step 3: Add heartbeat to Message**

```ruby
# app/models/message.rb
class Message < ApplicationRecord
  acts_as_message

  after_create_commit :trigger_heartbeat

  private

  def trigger_heartbeat
    return unless role == "user"
    # Always enqueue. Solid Queue's limits_concurrency (key: chat_ID) on LlmJob
    # ensures at most one runs per chat at a time. D22/D29.
    LlmJob.perform_later(chat)
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/models/message_test.rb`
Expected: All 3 tests PASS.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: heartbeat — always enqueue LlmJob on user message"
```

---

## Task 7: Routes and Controller

Name-based routing (`/chat/agents/chief_of_staff`) — no DB lookup needed, registry lookup instead.

**Files:**
- Create: `test/controllers/chats_controller_test.rb`
- Create: `app/controllers/chats_controller.rb`
- Modify: `config/routes.rb`

**Step 1: Write the failing test**

```ruby
# test/controllers/chats_controller_test.rb
require "test_helper"

class ChatsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Daan::AgentRegistry.clear
    @agent = Daan::Agent.new(
      name: "chief_of_staff", display_name: "Chief of Staff",
      model_name: "claude-sonnet-4-20250514", system_prompt: "You are CoS.", max_turns: 10
    )
    Daan::AgentRegistry.register(@agent)
  end

  teardown { Daan::AgentRegistry.clear }

  test "GET /chat shows the chat interface with agents in sidebar" do
    get chat_path
    assert_response :success
    assert_select "[data-testid='sidebar']"
    assert_select "[data-testid='agent-item']", count: 1
  end

  test "GET /chat/agents/:agent_name shows the agent's conversation" do
    chat = Chat.create!(agent_name: "chief_of_staff", model_id: "claude-sonnet-4-20250514")
    chat.messages.create!(role: "user", content: "Hello")

    get agent_chat_path("chief_of_staff")
    assert_response :success
    assert_select "[data-testid='message']", minimum: 1
  end

  test "POST /chat/agents/:agent_name/messages creates a user message and enqueues LlmJob" do
    assert_enqueued_with(job: LlmJob) do
      post agent_messages_path("chief_of_staff"),
           params: { message: { content: "Hello CoS" } }
    end

    assert_response :redirect
    assert_equal "user", Message.last.role
    assert_equal "Hello CoS", Message.last.content
  end

  test "POST creates a new chat if none exists for this agent" do
    assert_difference "Chat.count", 1 do
      post agent_messages_path("chief_of_staff"),
           params: { message: { content: "First message" } }
    end
  end

  test "raises KeyError for unknown agent name" do
    assert_raises(KeyError) { get agent_chat_path("nobody") }
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/chats_controller_test.rb`
Expected: FAIL — routes not defined.

**Step 3: Add routes**

```ruby
# config/routes.rb
Rails.application.routes.draw do
  root "chats#index"
  get "chat", to: "chats#index", as: :chat

  scope "chat" do
    get  "agents/:agent_name", to: "chats#show",          as: :agent_chat
    post "agents/:agent_name/messages", to: "chats#create_message", as: :agent_messages
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
```

**Step 4: Create controller**

```ruby
# app/controllers/chats_controller.rb
class ChatsController < ApplicationController
  before_action :set_agents
  before_action :set_agent, only: %i[show create_message]

  def index
    @agent = @agents.first
    render :show if @agent
  end

  def show
    @chat = current_chat_for(@agent)
  end

  def create_message
    @chat = current_chat_for(@agent) ||
            Chat.create!(agent_name: @agent.name, model_id: @agent.model_name)
    @chat.messages.create!(role: "user", content: params[:message][:content])
    redirect_to agent_chat_path(@agent)
  end

  private

  def set_agents
    @agents = Daan::AgentRegistry.all
  end

  def set_agent
    @agent = Daan::AgentRegistry.find(params[:agent_name])
  end

  def current_chat_for(agent)
    Chat.where(agent_name: agent.name).order(created_at: :desc).first
  end
end
```

Replace `model_id:` with the column name from Task 1 Step 6.

**Step 5: Create minimal view templates**

```erb
<%# app/views/chats/show.html.erb %>
<div class="flex h-screen" data-testid="chat-layout">
  <%= render "sidebar", agents: @agents, current_agent: @agent %>
  <main class="flex-1 flex flex-col overflow-hidden">
    <% if @chat %>
      <div data-testid="thread-view" class="flex-1 overflow-y-auto p-4">
        <div id="messages">
          <% @chat.messages.order(:created_at).each do |message| %>
            <div data-testid="message" class="mb-4 <%= message.role == 'user' ? 'text-right' : 'text-left' %>">
              <span class="inline-block max-w-lg px-4 py-2 rounded-lg
                <%= message.role == 'user' ? 'bg-blue-500 text-white' : 'bg-gray-200' %>">
                <%= message.content %>
              </span>
            </div>
          <% end %>
        </div>
      </div>
    <% end %>
    <% if @agent %>
      <div data-testid="compose-bar" class="border-t p-4">
        <%= form_with url: agent_messages_path(@agent), method: :post, class: "flex gap-2" do |f| %>
          <%= f.text_field :content, name: "message[content]",
              placeholder: "Message #{@agent.display_name}...",
              class: "flex-1 border rounded-lg px-4 py-2", autofocus: true %>
          <%= f.submit "Send", class: "bg-blue-500 text-white px-4 py-2 rounded-lg cursor-pointer" %>
        <% end %>
      </div>
    <% end %>
  </main>
</div>
```

```erb
<%# app/views/chats/_sidebar.html.erb %>
<aside data-testid="sidebar" class="w-64 bg-gray-900 text-white flex flex-col">
  <div class="p-4 font-bold text-lg border-b border-gray-700">Daan</div>
  <nav class="flex-1 p-2">
    <% agents.each do |agent| %>
      <%= link_to agent_chat_path(agent),
          class: "flex items-center gap-2 p-2 rounded hover:bg-gray-800 #{agent == current_agent ? 'bg-gray-800' : ''}",
          data: { testid: "agent-item" } do %>
        <span class="w-2 h-2 rounded-full <%= agent.busy? ? 'bg-yellow-400' : 'bg-green-400' %>"></span>
        <span><%= agent.display_name %></span>
      <% end %>
    <% end %>
  </nav>
</aside>
```

**Step 6: Run tests to verify they pass**

Run: `bin/rails test test/controllers/chats_controller_test.rb`
Expected: All 5 tests PASS.

**Step 7: Commit**

```bash
git add -A
git commit -m "feat: routes, controller, and minimal views"
```

---

## Task 8: ViewComponents with Lookbook Previews

Extract UI into proper ViewComponents. Every visual state gets a named Lookbook scenario.

**Files:**
- Create: `app/components/message_component.rb` + `.html.erb`
- Create: `app/components/agent_item_component.rb` + `.html.erb`
- Create: `app/components/compose_bar_component.rb` + `.html.erb`
- Create: `test/components/message_component_test.rb`
- Create: `test/components/agent_item_component_test.rb`
- Create: `test/components/previews/message_component_preview.rb`
- Create: `test/components/previews/agent_item_component_preview.rb`
- Create: `test/components/previews/compose_bar_component_preview.rb`
- Modify: `app/views/chats/show.html.erb`
- Modify: `app/views/chats/_sidebar.html.erb`

**Step 1: Write the failing component tests**

```ruby
# test/components/message_component_test.rb
require "test_helper"

class MessageComponentTest < ViewComponent::TestCase
  test "user message is right-aligned with blue background" do
    render_inline(MessageComponent.new(role: "user", content: "Hello"))
    assert_selector "[data-testid='message'][data-role='user']"
    assert_selector ".text-right"
    assert_selector ".bg-blue-500"
    assert_text "Hello"
  end

  test "assistant message is left-aligned with gray background" do
    render_inline(MessageComponent.new(role: "assistant", content: "Hi there"))
    assert_selector "[data-testid='message'][data-role='assistant']"
    assert_selector ".text-left"
    assert_selector ".bg-gray-200"
    assert_text "Hi there"
  end
end
```

```ruby
# test/components/agent_item_component_test.rb
require "test_helper"

class AgentItemComponentTest < ViewComponent::TestCase
  def agent(status: "idle")
    Daan::Agent.new(name: "chief_of_staff", display_name: "Chief of Staff",
                    model_name: "m", system_prompt: "p", max_turns: 10)
  end

  test "idle agent shows green dot" do
    render_inline(AgentItemComponent.new(agent: agent))
    assert_selector "[data-testid='agent-item']"
    assert_selector "#agent_chief_of_staff"
    assert_text "Chief of Staff"
    assert_selector ".bg-green-400"
  end

  test "active agent has highlighted background" do
    render_inline(AgentItemComponent.new(agent: agent, active: true))
    assert_selector ".bg-gray-800"
  end
end
```

Note: `busy?` calls `Chat.exists?(...)` — in component tests, stub it if needed:
```ruby
agent = Daan::Agent.new(...)
agent.stub(:busy?, true) { render_inline(AgentItemComponent.new(agent: agent)) }
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/components/`
Expected: FAIL — `NameError: uninitialized constant MessageComponent`

**Step 3: Implement MessageComponent**

```ruby
# app/components/message_component.rb
class MessageComponent < ViewComponent::Base
  def initialize(role:, content:, dom_id: nil)
    @role = role
    @content = content
    @dom_id = dom_id
  end

  private

  attr_reader :role, :content, :dom_id

  def alignment_classes = role == "user" ? "text-right" : "text-left"
  def bubble_classes = role == "user" ? "bg-blue-500 text-white" : "bg-gray-200 text-gray-900"
end
```

```erb
<%# app/components/message_component.html.erb %>
<div id="<%= dom_id %>"
     data-testid="message"
     data-role="<%= role %>"
     class="mb-4 <%= alignment_classes %>">
  <span class="inline-block max-w-lg px-4 py-2 rounded-lg <%= bubble_classes %>">
    <%= content %>
  </span>
</div>
```

**Step 4: Implement AgentItemComponent**

The `id` on the wrapper element is the Turbo Stream target for live status updates.

```ruby
# app/components/agent_item_component.rb
class AgentItemComponent < ViewComponent::Base
  def initialize(agent:, active: false)
    @agent = agent
    @active = active
  end

  private

  attr_reader :agent, :active

  def dot_classes = agent.busy? ? "bg-yellow-400" : "bg-green-400"
  def item_classes
    base = "flex items-center gap-2 p-2 rounded hover:bg-gray-800"
    active ? "#{base} bg-gray-800" : base
  end
end
```

```erb
<%# app/components/agent_item_component.html.erb %>
<div id="agent_<%= agent.name %>">
  <%= link_to agent_chat_path(agent), class: item_classes, data: { testid: "agent-item" } do %>
    <span class="w-2 h-2 rounded-full <%= dot_classes %>"></span>
    <span><%= agent.display_name %></span>
  <% end %>
</div>
```

**Step 5: Implement ComposeBarComponent**

```ruby
# app/components/compose_bar_component.rb
class ComposeBarComponent < ViewComponent::Base
  def initialize(agent:)
    @agent = agent
  end

  private

  attr_reader :agent
end
```

```erb
<%# app/components/compose_bar_component.html.erb %>
<div data-testid="compose-bar" class="border-t p-4">
  <%= form_with url: agent_messages_path(agent), method: :post, class: "flex gap-2" do |f| %>
    <%= f.text_field :content, name: "message[content]",
        placeholder: "Message #{agent.display_name}...",
        class: "flex-1 border rounded-lg px-4 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500",
        autofocus: true,
        data: { testid: "message-input" } %>
    <%= f.submit "Send",
        class: "bg-blue-500 hover:bg-blue-600 text-white px-4 py-2 rounded-lg cursor-pointer",
        data: { testid: "send-button" } %>
  <% end %>
</div>
```

**Step 6: Write Lookbook previews**

```ruby
# test/components/previews/message_component_preview.rb
class MessageComponentPreview < ViewComponent::Preview
  # Human sends a short message
  def user_message
    render MessageComponent.new(role: "user", content: "Hello, what can you help me with today?")
  end

  # Agent responds
  def assistant_message
    render MessageComponent.new(role: "assistant",
      content: "I'm the Chief of Staff. I can coordinate tasks and answer questions.")
  end

  # A long response that wraps
  def long_assistant_message
    render MessageComponent.new(role: "assistant",
      content: "This is a longer response that demonstrates how the bubble handles wrapping. " \
               "It should stay within max-w-lg and remain readable regardless of content length. " \
               "The padding and border-radius should stay consistent throughout.")
  end
end
```

```ruby
# test/components/previews/agent_item_component_preview.rb
class AgentItemComponentPreview < ViewComponent::Preview
  # Agent is idle — green dot
  def idle
    agent = Daan::Agent.new(name: "chief_of_staff", display_name: "Chief of Staff",
                            model_name: "m", system_prompt: "p", max_turns: 10)
    agent.stub(:busy?, false) { render AgentItemComponent.new(agent: agent) }
  end

  # Agent is busy on a task — yellow dot
  def busy
    agent = Daan::Agent.new(name: "chief_of_staff", display_name: "Chief of Staff",
                            model_name: "m", system_prompt: "p", max_turns: 10)
    agent.stub(:busy?, true) { render AgentItemComponent.new(agent: agent) }
  end

  # Agent is selected (current conversation) — highlighted background
  def active
    agent = Daan::Agent.new(name: "chief_of_staff", display_name: "Chief of Staff",
                            model_name: "m", system_prompt: "p", max_turns: 10)
    agent.stub(:busy?, false) { render AgentItemComponent.new(agent: agent, active: true) }
  end
end
```

```ruby
# test/components/previews/compose_bar_component_preview.rb
class ComposeBarComponentPreview < ViewComponent::Preview
  def default
    agent = Daan::Agent.new(name: "chief_of_staff", display_name: "Chief of Staff",
                            model_name: "m", system_prompt: "p", max_turns: 10)
    render ComposeBarComponent.new(agent: agent)
  end
end
```

**Step 7: Update views to use components**

```erb
<%# app/views/chats/show.html.erb %>
<div class="flex h-screen" data-testid="chat-layout">
  <%= render "sidebar", agents: @agents, current_agent: @agent %>
  <main class="flex-1 flex flex-col overflow-hidden">
    <% if @chat %>
      <div data-testid="thread-view" class="flex-1 overflow-y-auto p-4">
        <%= turbo_stream_from "chat_#{@chat.id}" %>
        <div id="messages">
          <% @chat.messages.order(:created_at).each do |message| %>
            <%= render MessageComponent.new(role: message.role, content: message.content,
                                           dom_id: "message_#{message.id}") %>
          <% end %>
        </div>
      </div>
    <% end %>
    <% if @agent %>
      <%= render ComposeBarComponent.new(agent: @agent) %>
    <% end %>
  </main>
</div>
```

```erb
<%# app/views/chats/_sidebar.html.erb %>
<aside data-testid="sidebar" class="w-64 bg-gray-900 text-white flex flex-col">
  <div class="p-4 font-bold text-lg border-b border-gray-700">Daan</div>
  <%= turbo_stream_from "agents" %>
  <nav class="flex-1 p-2">
    <% agents.each do |agent| %>
      <%= render AgentItemComponent.new(agent: agent, active: agent == current_agent) %>
    <% end %>
  </nav>
</aside>
```

**Step 8: Run all component tests**

Run: `bin/rails test test/components/`
Expected: All tests PASS.

**Step 9: Verify Lookbook**

Run: `bin/dev`
Visit: `http://localhost:3000/rails/lookbook`
Expected: Three component groups — MessageComponent (3 scenarios), AgentItemComponent (3 scenarios), ComposeBarComponent (1 scenario). All render correctly with Tailwind styles.

**Step 10: Commit**

```bash
git add -A
git commit -m "feat: ViewComponents with Lookbook previews for all UI states"
```

---

## Task 9: Turbo Stream Message Broadcasts

Push new messages to the browser in real time.

**Files:**
- Modify: `app/models/message.rb`
- Create: `test/models/message_broadcast_test.rb`

**Step 1: Write the failing test**

```ruby
# test/models/message_broadcast_test.rb
require "test_helper"

class MessageBroadcastTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    Daan::AgentRegistry.clear
    Daan::AgentRegistry.register(Daan::Agent.new(
      name: "test_agent", display_name: "TA", model_name: "m", system_prompt: "p", max_turns: 10
    ))
    @chat = Chat.create!(agent_name: "test_agent", model_id: "m")
  end

  teardown { Daan::AgentRegistry.clear }

  test "broadcasts to chat stream when a message is created" do
    assert_broadcasts("chat_#{@chat.id}", 1) do
      @chat.messages.create!(role: "assistant", content: "Hello")
    end
  end

  test "user message also broadcasts" do
    assert_broadcasts("chat_#{@chat.id}", 1) do
      @chat.messages.create!(role: "user", content: "Hi")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/message_broadcast_test.rb`
Expected: FAIL — 0 broadcasts.

**Step 3: Add broadcast to Message**

```ruby
# app/models/message.rb
class Message < ApplicationRecord
  acts_as_message

  after_create_commit :broadcast_message
  after_create_commit :trigger_heartbeat

  private

  def broadcast_message
    broadcast_append_to(
      "chat_#{chat_id}",
      target: "messages",
      renderable: MessageComponent.new(
        role: role,
        content: content,
        dom_id: "message_#{id}"
      )
    )
  end

  def trigger_heartbeat
    return unless role == "user"
    LlmJob.perform_later(chat)
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/models/message_broadcast_test.rb`
Expected: All 2 tests PASS.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: Turbo Stream message broadcasts via MessageComponent"
```

---

## Task 10: Agent Status Updates via Chat

When a chat's `task_status` changes, the agent's sidebar item updates in real time. Status is derived from task_status — no status column needed anywhere.

**Files:**
- Create: `test/models/chat_broadcast_test.rb`
- Modify: `app/models/chat.rb`

**Step 1: Write the failing test**

```ruby
# test/models/chat_broadcast_test.rb
require "test_helper"

class ChatBroadcastTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    Daan::AgentRegistry.clear
    Daan::AgentRegistry.register(Daan::Agent.new(
      name: "chief_of_staff", display_name: "CoS",
      model_name: "m", system_prompt: "p", max_turns: 10
    ))
    @chat = Chat.create!(agent_name: "chief_of_staff", model_id: "m")
  end

  teardown { Daan::AgentRegistry.clear }

  test "broadcasts AgentItemComponent to agents stream when task_status changes" do
    assert_broadcasts("agents", 1) do
      @chat.update!(task_status: "in_progress")
    end
  end

  test "broadcasts again when task completes" do
    @chat.update!(task_status: "in_progress")
    assert_broadcasts("agents", 1) do
      @chat.update!(task_status: "completed")
    end
  end

  test "does not broadcast when unrelated field changes" do
    assert_broadcasts("agents", 0) do
      @chat.update!(turn_count: 1)
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/chat_broadcast_test.rb`
Expected: FAIL — 0 broadcasts.

**Step 3: Add broadcast to Chat**

```ruby
# app/models/chat.rb
class Chat < ApplicationRecord
  acts_as_chat

  validates :agent_name, presence: true
  validates :task_status, presence: true,
    inclusion: { in: %w[pending in_progress completed failed blocked] }

  after_update_commit :broadcast_agent_status, if: :saved_change_to_task_status?

  def agent
    Daan::AgentRegistry.find(agent_name)
  end

  def max_turns_reached?
    agent.max_turns_reached?(turn_count)
  end

  private

  def broadcast_agent_status
    broadcast_replace_to(
      "agents",
      target: "agent_#{agent_name}",
      renderable: AgentItemComponent.new(agent: agent)
    )
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/models/chat_broadcast_test.rb`
Expected: All 3 tests PASS.

**Step 5: Run the full test suite**

Run: `bin/rails test`
Expected: ALL tests PASS.

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: live agent status in sidebar via Chat task_status broadcasts"
```

---

## Task 11: Initializer and Integration Smoke Test

**Files:**
- Create: `config/initializers/daan.rb`
- Modify: `db/seeds.rb`
- Create: `test/integration/chat_flow_test.rb`

**Step 1: Write the failing integration test**

```ruby
# test/integration/chat_flow_test.rb
require "test_helper"

class ChatFlowTest < ActionDispatch::IntegrationTest
  setup do
    Daan::AgentRegistry.clear
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
  end

  teardown { Daan::AgentRegistry.clear }

  test "sidebar shows loaded agents" do
    get chat_path
    assert_response :success
    assert_select "[data-testid='agent-item']", minimum: 1
    assert_select "[data-testid='agent-item']", text: /Chief of Staff/
  end

  test "full flow: send message, job enqueued, message saved" do
    agent = Daan::AgentRegistry.find("chief_of_staff")

    assert_enqueued_with(job: LlmJob) do
      post agent_messages_path(agent), params: { message: { content: "Hello CoS!" } }
    end

    assert_response :redirect
    chat = Chat.where(agent_name: "chief_of_staff").last
    assert_equal 1, chat.messages.count
    assert_equal "user", chat.messages.first.role
    assert_equal "Hello CoS!", chat.messages.first.content

    follow_redirect!
    assert_response :success
    assert_select "[data-testid='message']", minimum: 1
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/integration/chat_flow_test.rb`
Expected: FAIL — `KeyError: No agent registered: "chief_of_staff"` (registry is empty without loader).

**Step 3: Create initializer**

```ruby
# config/initializers/daan.rb
Rails.application.config.after_initialize do
  next if Rails.env.test? # Tests load the registry explicitly in setup
  Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
end
```

**Step 4: Update seeds**

```ruby
# db/seeds.rb
# Agents load from MD files at boot — no DB records needed.
# This file is here for future seed data (memories, initial chats, etc.)
puts "Agents available: #{Daan::AgentRegistry.all.map(&:display_name).join(', ')}"
```

**Step 5: Configure RubyLLM**

Edit `config/initializers/ruby_llm.rb`:

```ruby
RubyLLM.configure do |config|
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
end
```

**Step 6: Run integration tests**

Run: `bin/rails test test/integration/chat_flow_test.rb`
Expected: All 2 tests PASS.

**Step 7: Run the full test suite**

Run: `bin/rails test`
Expected: ALL tests PASS.

**Step 8: Commit**

```bash
git add -A
git commit -m "feat: initializer, seeds, and integration smoke test"
```

---

## Task 12: Manual Smoke Test

**Step 1: Set API key**

```bash
export ANTHROPIC_API_KEY=your-key-here
```

**Step 2: Start the server**

```bash
bin/dev
```

**Step 3: Verify Lookbook**

Visit `http://localhost:3000/rails/lookbook`
Expected: MessageComponent (3), AgentItemComponent (3), ComposeBarComponent (1) — all rendering correctly.

**Step 4: Use the app**

Visit `http://localhost:3000`

1. Sidebar shows "Chief of Staff" with green dot.
2. Click CoS. Empty thread with compose bar.
3. Type "Hello, what can you help me with?" and Send.
4. Your message appears right-aligned immediately.
5. Dot turns yellow (busy) — sidebar updates via Turbo Stream.
6. CoS responds left-aligned.
7. Dot returns green (idle).

**Step 5: Commit any final fixes**

```bash
git add -A
git commit -m "chore: V1 complete — human chats with Chief of Staff"
```

---

## Summary

| Task | What | Tests |
|------|------|-------|
| 1 | Add gems + install Tailwind, RubyLLM, Lookbook | — |
| 2 | `Daan::Agent` + `Daan::AgentRegistry` (plain Ruby, no DB) | 8 |
| 3 | Chat with `agent_name:string` + task state | 6 |
| 4 | Agent definition loader (MD files → AgentRegistry) | 3 |
| 5 | LlmJob with full conversation history | 6 |
| 6 | Heartbeat — always enqueue on user message | 3 |
| 7 | Routes, controller, minimal views | 5 |
| 8 | ViewComponents + Lookbook previews | 4+ |
| 9 | Turbo Stream message broadcasts | 2 |
| 10 | Agent status updates via Chat task_status | 3 |
| 11 | Initializer + integration smoke test | 2 |
| 12 | Manual smoke test + Lookbook verification | — |

**Total: 12 tasks, ~42 tests, 11 commits**

**Lookbook:** `http://localhost:3000/rails/lookbook` — browse all component states without touching the database.

**No `agents` table.** Agent status (idle/busy) is derived from `Chat.task_status`. Agent config lives in `Daan::AgentRegistry`, populated from `lib/daan/core/agents/*.md` at boot.
