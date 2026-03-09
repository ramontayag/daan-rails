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
gem "front_matter_parser"
gem "aasm"

group :development do
  gem "lookbook"
end

group :test do
  gem "vcr"
  gem "webmock"
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
git commit -m "build: add ruby_llm, tailwindcss-rails, view_component, lookbook, front_matter_parser, aasm, vcr, webmock gems"
```

---

## Task 2: Daan::Agent + AgentRegistry

Plain Ruby value objects. No migrations, no AR.

**Files:**
- Create: `lib/daan/agent.rb`
- Create: `lib/daan/agent_registry.rb`
- Create: `test/lib/daan/agent_test.rb`
- Create: `test/lib/daan/agent_registry_test.rb`
- Modify: `test/test_helper.rb`

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
    Chat.create!(agent_name: "chief_of_staff", model_id: "claude-sonnet-4-20250514").start!
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
    @agent = Daan::Agent.new(name: "chief_of_staff", display_name: "CoS",
                             model_name: "m", system_prompt: "p", max_turns: 10)
  end

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
      Chat.in_progress.exists?(agent_name: name)
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

**Step 4: Add global registry cleanup to test_helper**

Every test gets a clean `AgentRegistry` automatically — no per-class `setup`/`teardown` needed.

```ruby
# test/test_helper.rb
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    fixtures :all

    setup    { Daan::AgentRegistry.clear }
    teardown { Daan::AgentRegistry.clear }
  end
end
```

**Step 5: Run tests to verify they pass**

Run: `bin/rails test test/lib/daan/`
Expected: All 8 tests PASS.

**Step 6: Commit**

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
    @agent = Daan::Agent.new(name: "chief_of_staff", display_name: "CoS",
                             model_name: "claude-sonnet-4-20250514",
                             system_prompt: "You are CoS.", max_turns: 10)
    Daan::AgentRegistry.register(@agent)
  end

  test "agent returns the registered Daan::Agent" do
    chat = Chat.new(agent_name: "chief_of_staff")
    assert_equal @agent, chat.agent
  end

  test "defaults to pending state" do
    assert Chat.new.pending?
  end

  test "start! transitions pending to in_progress" do
    chat = chats(:hello_cos)
    chat.start!
    assert chat.in_progress?
  end

  test "complete! transitions in_progress to completed" do
    chat = chats(:hello_cos)
    chat.start!
    chat.finish!
    assert chat.completed?
  end

  test "invalid transition raises AASM::InvalidTransition" do
    chat = chats(:hello_cos)
    assert_raises(AASM::InvalidTransition) { chat.finish! }
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
  include AASM

  acts_as_chat

  validates :agent_name, presence: true

  aasm column: :task_status do
    state :pending, initial: true
    state :in_progress
    state :completed
    state :failed
    state :blocked

    event :start do
      transitions from: :pending, to: :in_progress
    end

    event :finish do
      transitions from: :in_progress, to: :completed
    end

    event :block do
      transitions from: :in_progress, to: :blocked
    end

    event :fail do
      transitions from: %i[pending in_progress], to: :failed
    end
  end

  def agent
    Daan::AgentRegistry.find(agent_name)
  end

  def max_turns_reached?
    agent.max_turns_reached?(turn_count)
  end
end
```

AASM provides: predicate methods (`chat.pending?`, `chat.in_progress?`, etc.), bang methods (`chat.start!`, `chat.finish!`, `chat.block!`, `chat.fail!`), and AR scopes (`Chat.pending`, `Chat.in_progress`, `Chat.completed`, etc.).

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
Expected: All 8 tests PASS.

**Step 8: Commit**

```bash
git add -A
git commit -m "feat: Chat with agent_name and AASM task state machine"
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
    @definitions_path = Rails.root.join("lib/daan/core/agents")
  end

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
    def self.parse(file_path)
      parsed = FrontMatterParser::Parser.parse_file(file_path.to_s)
      fm = parsed.front_matter

      {
        name: fm.fetch("name"),
        display_name: fm.fetch("display_name"),
        model_name: fm.fetch("model"),
        max_turns: fm.fetch("max_turns"),
        system_prompt: parsed.content.strip
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

## Task 5: Daan::ConversationRunner — The Agentic Loop

The service that drives one turn of conversation: set status, call `chat.complete` with streaming, broadcast chunks, update turn count and final status. `LlmJob` (Task 6) is a thin wrapper around this.

**Files:**
- Create: `test/lib/daan/conversation_runner_test.rb`
- Create: `lib/daan/conversation_runner.rb`

**How `chat.complete` works:** `acts_as_chat` adds a `complete` method that loads all existing messages from the DB, calls the LLM with full context, creates the assistant `Message` record, and streams chunks via a block. We never call `chat.ask(content)` — that would add another user message on top of the one the controller already saved.

Streaming means the assistant message exists in the DB immediately (RubyLLM creates it before the first chunk), and each chunk appends to the message's content div in the browser live. The "agent is typing..." signal for external apps (Slack, Campfire) is the `task_status: "in_progress"` broadcast from Task 10 — not a special DOM element.

**Step 1: Write the failing tests**

```ruby
# test/lib/daan/conversation_runner_test.rb
require "test_helper"

FakeChunk = Struct.new(:content)

class Daan::ConversationRunnerTest < ActiveSupport::TestCase
  setup do
    @agent = Daan::Agent.new(
      name: "test_agent", display_name: "Test Agent",
      model_name: "claude-haiku-4-5-20251001",
      system_prompt: "You are a test agent.",
      max_turns: 3
    )
    Daan::AgentRegistry.register(@agent)
    @chat = Chat.create!(agent_name: "test_agent", model_id: "claude-haiku-4-5-20251001")
    @chat.messages.create!(role: "user", content: "Hello agent")
  end

  test "saves an assistant message via complete" do
    stub_llm(@chat, "Hello human!") { Daan::ConversationRunner.call(@chat) }

    assert_equal 2, @chat.messages.count
    assert_equal "assistant", @chat.messages.last.role
    assert_equal "Hello human!", @chat.messages.last.content
  end

  test "streams chunks to the assistant message" do
    chunks_broadcast = []
    @chat.stub(:complete, ->(&block) {
      msg = @chat.messages.create!(role: "assistant", content: "Hello!")
      msg.stub(:broadcast_append_chunk, ->(c) { chunks_broadcast << c }) do
        block.call(FakeChunk.new("Hello!"))
      end
      msg
    }) do
      Daan::ConversationRunner.call(@chat)
    end

    assert_equal ["Hello!"], chunks_broadcast
  end

  test "increments turn_count" do
    stub_llm(@chat, "Hi") { Daan::ConversationRunner.call(@chat) }
    assert_equal 1, @chat.reload.turn_count
  end

  test "completes the task" do
    stub_llm(@chat, "Done") { Daan::ConversationRunner.call(@chat) }
    assert @chat.reload.completed?
  end

  test "blocks the task when max_turns reached" do
    @chat.update!(turn_count: @agent.max_turns - 1)
    stub_llm(@chat, "Last turn") { Daan::ConversationRunner.call(@chat) }
    assert @chat.reload.blocked?
  end

  test "fails the task and reraises on exception" do
    @chat.stub(:complete, ->(&block) { raise "LLM down" }) do
      assert_raises(RuntimeError) { Daan::ConversationRunner.call(@chat) }
    end
    assert @chat.reload.failed?
  end

  private

  # Simulates RubyLLM: creates the assistant message, yields one chunk, returns message.
  def stub_llm(chat, content)
    chat.stub(:complete, ->(&block) {
      msg = chat.messages.create!(role: "assistant", content: content)
      block.call(FakeChunk.new(content)) if block
      msg
    }) { yield }
  end
end
```

Replace `model_id:` with the column name from Task 1 Step 6.

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/lib/daan/conversation_runner_test.rb`
Expected: FAIL — `NameError: uninitialized constant Daan::ConversationRunner`

**Step 3: Implement ConversationRunner**

```ruby
# lib/daan/conversation_runner.rb
module Daan
  class ConversationRunner
    def self.call(chat)
      agent = chat.agent
      chat.start!
      chat.broadcast_agent_status

      # complete processes messages already in the DB, calls the LLM with full
      # history, persists the assistant message, and yields streaming chunks.
      assistant_message = nil
      chat.complete do |chunk|
        next unless chunk.content.present?
        # RubyLLM creates the assistant Message before the first chunk — memoize it.
        assistant_message ||= chat.messages.where(role: "assistant").last
        assistant_message&.broadcast_append_chunk(chunk.content)
      end

      chat.increment!(:turn_count)

      agent.max_turns_reached?(chat.turn_count) ? chat.block! : chat.finish!
      chat.broadcast_agent_status
    rescue
      chat.fail!
      chat.broadcast_agent_status
      raise
    end
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/lib/daan/conversation_runner_test.rb`
Expected: All 6 tests PASS.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: Daan::ConversationRunner service"
```

---

## Task 6: LlmJob — Thin Wrapper with VCR Integration Test

`LlmJob` delegates entirely to `Daan::ConversationRunner`. One integration test records a real API call via VCR so the full stack is exercised once and replayed cheaply thereafter.

**Files:**
- Modify: `test/test_helper.rb`
- Create: `test/jobs/llm_job_test.rb`
- Create: `app/jobs/llm_job.rb`
- Auto-created: `test/vcr_cassettes/llm_job/complete.yml` (on first run)

**Step 1: Configure VCR in test_helper**

Add to `test/test_helper.rb`:

```ruby
require "vcr"
require "webmock/minitest"

VCR.configure do |config|
  config.cassette_library_dir = "test/vcr_cassettes"
  config.hook_into :webmock
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV["ANTHROPIC_API_KEY"] }
  config.default_cassette_options = { record: :new_episodes }
end
```

**Step 2: Write the failing integration test**

```ruby
# test/jobs/llm_job_test.rb
require "test_helper"

class LlmJobTest < ActiveSupport::TestCase
  setup do
    Daan::AgentRegistry.register(Daan::Agent.new(
      name: "cos", display_name: "Chief of Staff",
      model_name: "claude-haiku-4-5-20251001",
      system_prompt: "You are a helpful assistant. Reply in one sentence.",
      max_turns: 10
    ))
    @chat = Chat.create!(agent_name: "cos", model_id: "claude-haiku-4-5-20251001")
    @chat.messages.create!(role: "user", content: "Say hello.")
  end

  test "processes the conversation and marks it completed" do
    VCR.use_cassette("llm_job/complete") do
      LlmJob.perform_now(@chat)
    end

    @chat.reload
    assert_equal "completed", @chat.task_status
    assert_equal 1, @chat.turn_count
    assert @chat.messages.where(role: "assistant").exists?
  end
end
```

Replace `model_id:` with the column name from Task 1 Step 6.

**Step 3: Run to verify it fails**

Run: `bin/rails test test/jobs/llm_job_test.rb`
Expected: FAIL — `NameError: uninitialized constant LlmJob`

**Step 4: Implement LlmJob**

```ruby
# app/jobs/llm_job.rb
class LlmJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: ->(chat) { "chat_#{chat.id}" }

  def perform(chat)
    Daan::ConversationRunner.call(chat)
  end
end
```

**Step 5: Run the integration test**

Run: `ANTHROPIC_API_KEY=your_key bin/rails test test/jobs/llm_job_test.rb`

First run: makes a real API call and records `test/vcr_cassettes/llm_job/complete.yml`.
Subsequent runs: replays the cassette — no API key needed, no network.

Expected: 1 test PASS.

**Step 6: Commit (include the cassette)**

```bash
git add -A
git commit -m "feat: LlmJob thin wrapper + VCR integration test"
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
    @agent = Daan::Agent.new(
      name: "chief_of_staff", display_name: "Chief of Staff",
      model_name: "claude-sonnet-4-20250514", system_prompt: "You are CoS.", max_turns: 10
    )
    Daan::AgentRegistry.register(@agent)
  end

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
    # Always enqueue. Solid Queue's limits_concurrency (key: chat_ID) ensures
    # at most one LlmJob runs per chat at a time. D22/D29.
    LlmJob.perform_later(@chat)
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

class MessageComponentTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  test "user message has correct data attributes and alignment" do
    render_inline(MessageComponent.new(role: "user", content: "Hello"))
    assert_includes rendered_content, 'data-testid="message"'
    assert_includes rendered_content, 'data-role="user"'
    assert_includes rendered_content, "text-right"
    assert_includes rendered_content, "bg-blue-500"
    assert_includes rendered_content, "Hello"
  end

  test "assistant message has correct data attributes and alignment" do
    render_inline(MessageComponent.new(role: "assistant", content: "Hi there"))
    assert_includes rendered_content, 'data-role="assistant"'
    assert_includes rendered_content, "text-left"
    assert_includes rendered_content, "bg-gray-200"
    assert_includes rendered_content, "Hi there"
  end

  test "renders a content div with stable ID when message record provided" do
    # The content div is the Turbo Stream target for streaming chunks.
    # Its ID must match what broadcast_append_chunk targets.
    agent = Daan::Agent.new(name: "a", display_name: "A", model_name: "m",
                            system_prompt: "p", max_turns: 10)
    Daan::AgentRegistry.register(agent)
    chat = Chat.create!(agent_name: "a", model_id: "m")
    message = chat.messages.create!(role: "assistant", content: "Hi")

    render_inline(MessageComponent.new(message: message))

    assert_includes rendered_content, "content_message_#{message.id}"
    assert_includes rendered_content, "Hi"
  end

  test "renders without a message record (previews, initial render)" do
    render_inline(MessageComponent.new(role: "user", content: "Hello"))
    assert_includes rendered_content, "Hello"
  end
end
```

```ruby
# test/components/agent_item_component_test.rb
require "test_helper"

class AgentItemComponentTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  def agent
    Daan::Agent.new(name: "chief_of_staff", display_name: "Chief of Staff",
                    model_name: "m", system_prompt: "p", max_turns: 10)
  end

  test "idle agent shows name and green dot" do
    render_inline(AgentItemComponent.new(agent: agent))
    assert_includes rendered_content, 'data-testid="agent-item"'
    assert_includes rendered_content, 'id="agent_chief_of_staff"'
    assert_includes rendered_content, "Chief of Staff"
    assert_includes rendered_content, "bg-green-400"
  end

  test "active agent has highlighted background" do
    render_inline(AgentItemComponent.new(agent: agent, active: true))
    assert_includes rendered_content, "bg-gray-800"
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

When a `message:` AR record is provided, the component renders with stable IDs so streaming chunks can be appended. `wrapper_id` targets the whole bubble (for Turbo replace); `content_id` targets the text inside (for chunk appending). Without a record (Lookbook previews, etc.) both IDs are nil.

```ruby
# app/components/message_component.rb
class MessageComponent < ViewComponent::Base
  def initialize(role: nil, content: nil, message: nil)
    if message
      @role    = message.role
      @content = message.content
      @wrapper_id = "message_#{message.id}"
      @content_id = "content_message_#{message.id}"
    else
      @role    = role
      @content = content
    end
  end

  private

  attr_reader :role, :content, :wrapper_id, :content_id

  def alignment_classes = role == "user" ? "text-right" : "text-left"
  def bubble_classes    = role == "user" ? "bg-blue-500 text-white" : "bg-gray-200 text-gray-900"
end
```

```erb
<%# app/components/message_component.html.erb %>
<div id="<%= wrapper_id %>"
     data-testid="message"
     data-role="<%= role %>"
     class="mb-4 <%= alignment_classes %>">
  <span class="inline-block max-w-lg px-4 py-2 rounded-lg <%= bubble_classes %>">
    <div id="<%= content_id %>"><%= content %></div>
  </span>
</div>
```

The `content_id` (`content_message_123`) is the Turbo Stream target that `broadcast_append_chunk` appends to.

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

Push new messages to the browser in real time. Assistant messages render as an empty bubble immediately on creation; LlmJob then appends streaming chunks into the bubble via `broadcast_append_chunk`.

**Files:**
- Modify: `app/models/message.rb`
- Create: `test/models/message_broadcast_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/models/message_broadcast_test.rb
require "test_helper"

class MessageBroadcastTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    Daan::AgentRegistry.register(Daan::Agent.new(
      name: "test_agent", display_name: "TA", model_name: "m", system_prompt: "p", max_turns: 10
    ))
    @chat = Chat.create!(agent_name: "test_agent", model_id: "m")
  end

  test "broadcasts to chat stream when an assistant message is created" do
    assert_broadcasts("chat_#{@chat.id}", 1) do
      @chat.messages.create!(role: "assistant", content: "Hello")
    end
  end

  test "user message also broadcasts" do
    assert_broadcasts("chat_#{@chat.id}", 1) do
      @chat.messages.create!(role: "user", content: "Hi")
    end
  end

  test "broadcast_append_chunk appends to content div" do
    message = @chat.messages.create!(role: "assistant", content: "")
    assert_broadcasts("chat_#{@chat.id}", 1) do
      message.broadcast_append_chunk("Hello")
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/message_broadcast_test.rb`
Expected: FAIL — 0 broadcasts, and `broadcast_append_chunk` not defined.

**Step 3: Add broadcasts to Message**

```ruby
# app/models/message.rb
class Message < ApplicationRecord
  acts_as_message

  after_create_commit :broadcast_message

  def broadcast_append_chunk(chunk_content)
    broadcast_append_to(
      "chat_#{chat_id}",
      target: "content_message_#{id}",
      html: chunk_content
    )
  end

  private

  def broadcast_message
    broadcast_append_to(
      "chat_#{chat_id}",
      target: "messages",
      renderable: MessageComponent.new(message: self)
    )
  end

end
```

`broadcast_message` passes `message: self` so `MessageComponent` renders the `content_message_#{id}` div that chunk appends target.

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/models/message_broadcast_test.rb`
Expected: All 3 tests PASS.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: Turbo Stream message broadcasts with streaming chunk support"
```

---

## Task 10: Agent Status Updates via Chat

`Chat` exposes a `broadcast_agent_status` method. `ConversationRunner` calls it explicitly after each state transition — no AR callback involved.

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
    Daan::AgentRegistry.register(Daan::Agent.new(
      name: "chief_of_staff", display_name: "CoS",
      model_name: "m", system_prompt: "p", max_turns: 10
    ))
    @chat = Chat.create!(agent_name: "chief_of_staff", model_id: "m")
  end

  test "broadcast_agent_status sends AgentItemComponent to the agents stream" do
    assert_broadcasts("agents", 1) do
      @chat.broadcast_agent_status
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/chat_broadcast_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'broadcast_agent_status'`

**Step 3: Add broadcast method to Chat**

```ruby
# app/models/chat.rb
class Chat < ApplicationRecord
  include AASM

  acts_as_chat

  validates :agent_name, presence: true

  aasm column: :task_status do
    state :pending, initial: true
    state :in_progress
    state :completed
    state :failed
    state :blocked

    event :start do
      transitions from: :pending, to: :in_progress
    end

    event :finish do
      transitions from: :in_progress, to: :completed
    end

    event :block do
      transitions from: :in_progress, to: :blocked
    end

    event :fail do
      transitions from: %i[pending in_progress], to: :failed
    end
  end

  def agent
    Daan::AgentRegistry.find(agent_name)
  end

  def max_turns_reached?
    agent.max_turns_reached?(turn_count)
  end

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
Expected: 1 test PASS.

**Step 5: Run the full test suite**

Run: `bin/rails test`
Expected: ALL tests PASS.

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: Chat#broadcast_agent_status public method for callers"
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
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
  end

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
| 3 | Chat with `agent_name:string` + AASM task state machine | 8 |
| 4 | Agent definition loader (MD files → AgentRegistry) | 3 |
| 5 | `Daan::ConversationRunner` service (unit tests, stubbed LLM) | 6 |
| 6 | `LlmJob` thin wrapper (1 VCR integration test, real API) | 1 |
| 7 | Routes, controller, minimal views — controller enqueues LlmJob | 5 |
| 8 | ViewComponents + Lookbook previews | 4+ |
| 9 | Turbo Stream message broadcasts + streaming chunks | 3 |
| 10 | `Chat#broadcast_agent_status` public method; called by ConversationRunner | 1 |
| 11 | Initializer + integration smoke test | 2 |
| 12 | Manual smoke test + Lookbook verification | — |

**Total: 12 tasks, ~41 tests, 11 commits**

**Lookbook:** `http://localhost:3000/rails/lookbook` — browse all component states without touching the database.

**No `agents` table.** Agent status (idle/busy) is derived from `Chat.task_status`. Agent config lives in `Daan::AgentRegistry`, populated from `lib/daan/core/agents/*.md` at boot.
