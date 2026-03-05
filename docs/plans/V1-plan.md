# V1: Human Chats With One Agent — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Human sends a message to the Chief of Staff agent and receives an LLM response in a Slack-like chat UI.

**Architecture:** RubyLLM handles the LLM abstraction and message persistence via `acts_as_chat`/`acts_as_message`. Solid Queue drives the job chain (one LLM Job per turn). Turbo Streams push messages to the browser in real time. A custom Agent model + loader reads agent definitions from frontmatter Markdown files. Tailwind CSS + ViewComponents for the UI.

**Tech Stack:** Rails 8.1, SQLite, RubyLLM, Solid Queue, Turbo Streams, Tailwind CSS, ViewComponent, Lookbook

**Naming note:** RubyLLM's `Chat` = Daan's "thread" (D19). A `Chat` is one conversation thread tied to one task/LLM session. `Thread` is a reserved Ruby class name, so we use `Chat`. An `Agent` is our custom model. Task state (turn_count, status) lives on `Chat` directly since D19 says thread = task = session (1:1 in V1).

---

## Task 1: Add Gems

**Files:**
- Modify: `Gemfile`

**Step 1: Add gems to Gemfile**

Add these lines to the Gemfile (after the existing gems, before the groups):

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
Expected: Creates migrations for `chats`, `messages`, `tool_calls`, `models` tables. Creates model files with `acts_as_*` declarations. Creates `config/initializers/ruby_llm.rb`.

**Step 5: Install Lookbook**

Run: `bin/rails generate lookbook:install`
Expected: Mounts Lookbook at `/rails/lookbook` in development. Creates `test/components/previews/` directory.

**Step 6: Verify generated files exist**

Check that these files were created:
- `app/models/chat.rb`
- `app/models/message.rb`
- `app/models/tool_call.rb`
- `db/migrate/*_create_chats.rb`
- `db/migrate/*_create_messages.rb`

**Step 7: Run migrations**

Run: `bin/rails db:migrate`
Expected: Tables created successfully.

**Step 8: Commit**

```bash
git add -A
git commit -m "build: add ruby_llm, tailwindcss-rails, view_component, lookbook gems"
```

---

## Task 2: Agent Model

**Files:**
- Create: `test/models/agent_test.rb`
- Create: `db/migrate/TIMESTAMP_create_agents.rb` (via generator)
- Create: `app/models/agent.rb`
- Create: `test/fixtures/agents.yml`

**Step 1: Write the failing test**

```ruby
# test/models/agent_test.rb
require "test_helper"

class AgentTest < ActiveSupport::TestCase
  test "valid agent with all required fields" do
    agent = Agent.new(
      name: "chief_of_staff",
      display_name: "Chief of Staff",
      status: "idle",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You are the Chief of Staff.",
      max_turns: 10
    )
    assert agent.valid?
  end

  test "requires name" do
    agent = Agent.new(name: nil)
    assert_not agent.valid?
    assert_includes agent.errors[:name], "can't be blank"
  end

  test "requires unique name" do
    Agent.create!(name: "chief_of_staff", display_name: "CoS", status: "idle",
                  model_name: "claude-sonnet-4-20250514", system_prompt: "You are CoS.", max_turns: 10)
    duplicate = Agent.new(name: "chief_of_staff", display_name: "CoS", status: "idle",
                          model_name: "claude-sonnet-4-20250514", system_prompt: "You are CoS.", max_turns: 10)
    assert_not duplicate.valid?
  end

  test "status defaults to idle" do
    agent = Agent.new
    assert_equal "idle", agent.status
  end

  test "status must be idle or busy" do
    agent = agents(:chief_of_staff)
    agent.status = "idle"
    assert agent.valid?
    agent.status = "busy"
    assert agent.valid?
    agent.status = "banana"
    assert_not agent.valid?
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/agent_test.rb`
Expected: FAIL — `NameError: uninitialized constant Agent`

**Step 3: Generate the migration**

Run: `bin/rails generate migration CreateAgents name:string:uniq display_name:string status:string model_name:string system_prompt:text max_turns:integer`

Then edit the migration to add defaults and not-null constraints:

```ruby
class CreateAgents < ActiveRecord::Migration[8.1]
  def change
    create_table :agents do |t|
      t.string :name, null: false
      t.string :display_name, null: false
      t.string :status, null: false, default: "idle"
      t.string :model_name, null: false
      t.text :system_prompt, null: false
      t.integer :max_turns, null: false, default: 10

      t.timestamps
    end

    add_index :agents, :name, unique: true
  end
end
```

**Step 4: Run migration**

Run: `bin/rails db:migrate`

**Step 5: Create the Agent model**

```ruby
# app/models/agent.rb
class Agent < ApplicationRecord
  has_many :chats, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :display_name, presence: true
  validates :model_name, presence: true
  validates :system_prompt, presence: true
  validates :max_turns, presence: true, numericality: { greater_than: 0 }
  validates :status, presence: true, inclusion: { in: %w[idle busy] }
end
```

**Step 6: Create fixtures**

```yaml
# test/fixtures/agents.yml
chief_of_staff:
  name: chief_of_staff
  display_name: Chief of Staff
  status: idle
  model_name: claude-sonnet-4-20250514
  system_prompt: You are the Chief of Staff.
  max_turns: 10
```

**Step 7: Run tests to verify they pass**

Run: `bin/rails test test/models/agent_test.rb`
Expected: All 5 tests PASS.

**Step 8: Commit**

```bash
git add -A
git commit -m "feat: add Agent model with validations"
```

---

## Task 3: Extend Chat with Agent and Task State

RubyLLM's generator already created the `Chat` model with `acts_as_chat`. We need to add: `agent_id`, `task_status`, `turn_count` columns. This makes Chat = thread = task (D19).

**Files:**
- Create: `test/models/chat_test.rb`
- Create: `db/migrate/TIMESTAMP_add_agent_and_task_fields_to_chats.rb`
- Modify: `app/models/chat.rb`
- Create: `test/fixtures/chats.yml`

**Step 1: Write the failing test**

```ruby
# test/models/chat_test.rb
require "test_helper"

class ChatTest < ActiveSupport::TestCase
  test "belongs to an agent" do
    chat = chats(:hello_cos)
    assert_equal agents(:chief_of_staff), chat.agent
  end

  test "task_status defaults to pending" do
    chat = Chat.new
    assert_equal "pending", chat.task_status
  end

  test "task_status transitions: pending to in_progress" do
    chat = chats(:hello_cos)
    assert_equal "pending", chat.task_status
    chat.update!(task_status: "in_progress")
    assert_equal "in_progress", chat.task_status
  end

  test "task_status must be a valid state" do
    chat = chats(:hello_cos)
    chat.task_status = "dancing"
    assert_not chat.valid?
  end

  test "turn_count defaults to 0" do
    chat = Chat.new
    assert_equal 0, chat.turn_count
  end

  test "max_turns comes from agent" do
    chat = chats(:hello_cos)
    assert_equal chat.agent.max_turns, chat.max_turns
  end

  test "max_turns_reached? when turn_count >= agent max_turns" do
    chat = chats(:hello_cos)
    chat.turn_count = chat.agent.max_turns
    assert chat.max_turns_reached?
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/chat_test.rb`
Expected: FAIL — missing columns/methods.

**Step 3: Generate migration**

Run: `bin/rails generate migration AddAgentAndTaskFieldsToChats agent:references task_status:string turn_count:integer`

Edit the migration:

```ruby
class AddAgentAndTaskFieldsToChats < ActiveRecord::Migration[8.1]
  def change
    add_reference :chats, :agent, null: false, foreign_key: true
    add_column :chats, :task_status, :string, null: false, default: "pending"
    add_column :chats, :turn_count, :integer, null: false, default: 0
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

  belongs_to :agent

  validates :task_status, presence: true,
    inclusion: { in: %w[pending in_progress completed failed blocked] }

  def max_turns
    agent.max_turns
  end

  def max_turns_reached?
    turn_count >= max_turns
  end
end
```

**Step 6: Create fixtures**

```yaml
# test/fixtures/chats.yml
hello_cos:
  agent: chief_of_staff
  task_status: pending
  turn_count: 0
  model_id: claude-sonnet-4-20250514
```

Note: The `model_id` column comes from RubyLLM's `acts_as_chat`. Check the generated migration for the exact column name — it may be `model_id` (string, storing the model identifier like "claude-sonnet-4-20250514"). Adjust the fixture to match.

**Step 7: Run tests to verify they pass**

Run: `bin/rails test test/models/chat_test.rb`
Expected: All 7 tests PASS.

**Step 8: Commit**

```bash
git add -A
git commit -m "feat: extend Chat with agent reference and task state"
```

---

## Task 4: Agent Definition Loader

Reads a frontmatter Markdown file and syncs an Agent record to the DB.

**Files:**
- Create: `test/lib/daan/agent_loader_test.rb`
- Create: `lib/daan/agent_loader.rb`
- Create: `lib/daan/core/agents/chief_of_staff.md`

**Step 1: Create the agent definition file**

```markdown
---
name: chief_of_staff
display_name: Chief of Staff
model: claude-sonnet-4-20250514
max_turns: 10
---

You are the Chief of Staff for the Daan agent team.

You are the primary point of contact for the human user. When the human asks you to do something, you assess the request, break it down if needed, and coordinate with other agents to get it done.

For now, you handle all requests directly since you are the only agent available.

Be concise, helpful, and proactive. Ask clarifying questions when the request is ambiguous.
```

**Step 2: Write the failing test**

```ruby
# test/lib/daan/agent_loader_test.rb
require "test_helper"

class Daan::AgentLoaderTest < ActiveSupport::TestCase
  setup do
    @definitions_path = Rails.root.join("lib/daan/core/agents")
  end

  test "loads agent definition from markdown file" do
    definition = Daan::AgentLoader.parse(@definitions_path.join("chief_of_staff.md"))

    assert_equal "chief_of_staff", definition[:name]
    assert_equal "Chief of Staff", definition[:display_name]
    assert_equal "claude-sonnet-4-20250514", definition[:model_name]
    assert_equal 10, definition[:max_turns]
    assert_includes definition[:system_prompt], "Chief of Staff"
  end

  test "sync! creates agent record from definition file" do
    Agent.where(name: "chief_of_staff").destroy_all

    Daan::AgentLoader.sync!(@definitions_path)

    agent = Agent.find_by!(name: "chief_of_staff")
    assert_equal "Chief of Staff", agent.display_name
    assert_equal "claude-sonnet-4-20250514", agent.model_name
    assert_equal 10, agent.max_turns
    assert_includes agent.system_prompt, "Chief of Staff"
  end

  test "sync! updates existing agent if definition changed" do
    Agent.where(name: "chief_of_staff").destroy_all
    Agent.create!(name: "chief_of_staff", display_name: "Old Name", status: "idle",
                  model_name: "old-model", system_prompt: "Old prompt", max_turns: 5)

    Daan::AgentLoader.sync!(@definitions_path)

    agent = Agent.find_by!(name: "chief_of_staff")
    assert_equal "Chief of Staff", agent.display_name
    assert_equal "claude-sonnet-4-20250514", agent.model_name
  end

  test "sync! loads all .md files in directory" do
    agents = Daan::AgentLoader.load_all(@definitions_path)
    assert agents.any? { |a| a[:name] == "chief_of_staff" }
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

      frontmatter = YAML.safe_load(match[1], permitted_classes: [Symbol])
      body = match[2].strip

      {
        name: frontmatter.fetch("name"),
        display_name: frontmatter.fetch("display_name"),
        model_name: frontmatter.fetch("model"),
        max_turns: frontmatter.fetch("max_turns"),
        system_prompt: body
      }
    end

    def self.load_all(directory)
      Dir.glob(directory.join("*.md")).map { |f| parse(f) }
    end

    def self.sync!(directory)
      load_all(directory).each do |definition|
        agent = Agent.find_or_initialize_by(name: definition[:name])
        agent.update!(
          display_name: definition[:display_name],
          model_name: definition[:model_name],
          max_turns: definition[:max_turns],
          system_prompt: definition[:system_prompt]
        )
      end
    end
  end
end
```

**Step 5: Run tests to verify they pass**

Run: `bin/rails test test/lib/daan/agent_loader_test.rb`
Expected: All 4 tests PASS.

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: agent definition loader from frontmatter markdown"
```

---

## Task 5: LlmJob — The Heartbeat

The core job: load chat messages, call RubyLLM, save response, update task state.

**Files:**
- Create: `test/jobs/llm_job_test.rb`
- Create: `app/jobs/llm_job.rb`

**Architecture note — pre-saved user messages:**

The controller saves the user's message immediately (for instant Turbo Stream display). This means when LlmJob runs, the user message is already in `chat.messages`. We cannot use `chat.ask(content)` — that would add the user message a second time. Instead, the job builds the full conversation history from all saved messages and calls RubyLLM's lower-level API to get a completion.

The stub target is `chat` itself (the `complete` method, or whatever RubyLLM exposes for "send these messages, get a completion"). **Verify the exact method during Task 1** by reading the generated model from `rails generate ruby_llm:install` — look for what `acts_as_chat` adds to the model beyond `ask`. If no such method exists, build history manually: `RubyLLM.chat(messages: built_array).complete`.

**Step 1: Write the failing test**

```ruby
# test/jobs/llm_job_test.rb
require "test_helper"

FakeResponse = Struct.new(:content)

class LlmJobTest < ActiveSupport::TestCase
  setup do
    @agent = Agent.create!(
      name: "test_agent", display_name: "Test Agent", status: "idle",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You are a test agent. Reply with short answers.",
      max_turns: 3
    )
    @chat = Chat.create!(agent: @agent, model_id: @agent.model_name)
    @chat.messages.create!(role: "user", content: "Hello agent")
  end

  test "calls LLM and saves assistant message" do
    stub_llm(@chat, "Hello human!") { LlmJob.perform_now(@chat) }

    assert_equal 2, @chat.messages.count
    assert_equal "assistant", @chat.messages.last.role
    assert_equal "Hello human!", @chat.messages.last.content
  end

  test "sends full conversation history to LLM, not just last message" do
    # Add a prior turn so history has 3 messages
    @chat.messages.create!(role: "assistant", content: "Hi there")
    @chat.messages.create!(role: "user", content: "Follow-up question")

    captured_messages = nil
    @chat.stub(:complete, ->(messages:, **) {
      captured_messages = messages
      FakeResponse.new("Got it")
    }) do
      LlmJob.perform_now(@chat)
    end

    # All 3 prior messages must be in context — not just the last one
    assert_equal 3, captured_messages.length
    assert_equal "user", captured_messages.first[:role]
    assert_equal "Hello agent", captured_messages.first[:content]
  end

  test "increments turn_count" do
    stub_llm(@chat, "Hi") { LlmJob.perform_now(@chat) }
    assert_equal 1, @chat.reload.turn_count
  end

  test "sets task_status to completed after text response" do
    stub_llm(@chat, "Done") { LlmJob.perform_now(@chat) }
    assert_equal "completed", @chat.reload.task_status
  end

  test "sets task_status to blocked when max_turns reached" do
    @chat.update!(turn_count: @agent.max_turns - 1)
    stub_llm(@chat, "Blocked") { LlmJob.perform_now(@chat) }
    assert_equal "blocked", @chat.reload.task_status
  end

  test "agent is idle after job completes" do
    stub_llm(@chat, "Working") { LlmJob.perform_now(@chat) }
    assert_equal "idle", @chat.agent.reload.status
  end

  test "sets task_status to failed and reraises on exception" do
    @chat.stub(:complete, ->(**) { raise "LLM down" }) do
      assert_raises(RuntimeError) { LlmJob.perform_now(@chat) }
    end
    assert_equal "failed", @chat.reload.task_status
    assert_equal "idle", @chat.agent.reload.status
  end

  private

  def stub_llm(chat, response_content)
    chat.stub(:complete, ->(**) { FakeResponse.new(response_content) }) do
      yield
    end
  end
end
```

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
    chat.update!(task_status: "in_progress")
    chat.agent.update!(status: "busy")

    # Build full conversation history from all saved messages.
    # The user message was already saved by the controller for instant display —
    # we must NOT call chat.ask() here as that would add the user message again.
    messages = chat.messages.order(:created_at).map do |m|
      { role: m.role, content: m.content }
    end

    # complete() sends the full history and returns the assistant response.
    # Verify the exact method name from acts_as_chat during Task 1 step 6.
    # If acts_as_chat doesn't expose this, use:
    #   RubyLLM.chat(messages: messages)
    #     .with_model(chat.agent.model_name)
    #     .with_instructions(chat.agent.system_prompt)
    #     .complete
    response = chat.complete(
      messages: messages,
      model: chat.agent.model_name,
      instructions: chat.agent.system_prompt
    )

    chat.messages.create!(role: "assistant", content: response.content)
    chat.increment!(:turn_count)

    if chat.max_turns_reached?
      chat.update!(task_status: "blocked")
    else
      chat.update!(task_status: "completed")
    end

    chat.agent.update!(status: "idle")
  rescue => e
    chat.update!(task_status: "failed")
    chat.agent.update!(status: "idle")
    raise
  end
end
```

**Implementation note:** The `chat.complete(messages:, model:, instructions:)` call above is illustrative. Verify the actual signature from the RubyLLM source after running `rails generate ruby_llm:install`. The key invariant the tests enforce: **all messages in `chat.messages` must be passed as context** — not just the last one.

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/jobs/llm_job_test.rb`
Expected: All 6 tests PASS. Adjust stubs if RubyLLM's API differs.

**Step 5: Commit**

```bash
git add -A
git commit -m "feat: LlmJob with turn counting and concurrency control"
```

---

## Task 6: Heartbeat — Auto-Enqueue LlmJob on New Message

When a new user message is created in a chat with no in-flight LlmJob, enqueue one (D29).

**Files:**
- Create: `test/models/message_test.rb`
- Modify: `app/models/message.rb`

**Step 1: Write the failing test**

```ruby
# test/models/message_test.rb
require "test_helper"

class MessageTest < ActiveSupport::TestCase
  setup do
    @agent = Agent.create!(
      name: "heartbeat_agent", display_name: "HB Agent", status: "idle",
      model_name: "claude-sonnet-4-20250514", system_prompt: "Test", max_turns: 10
    )
    @chat = Chat.create!(agent: @agent, model_id: @agent.model_name)
  end

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

  test "always enqueues LlmJob for user messages regardless of task_status" do
    # Solid Queue's concurrency_key (limits_concurrency to: 1) is the deduplication
    # mechanism — not task_status. If a job is already running, Solid Queue queues
    # the second one and runs it after the first completes.
    @chat.update!(task_status: "in_progress")

    assert_enqueued_with(job: LlmJob) do
      @chat.messages.create!(role: "user", content: "Follow-up while busy")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/message_test.rb`
Expected: FAIL — first test fails (no job enqueued).

**Step 3: Add heartbeat callback to Message**

```ruby
# app/models/message.rb
class Message < ApplicationRecord
  acts_as_message

  after_create_commit :trigger_heartbeat

  private

  def trigger_heartbeat
    return unless role == "user"

    # Always enqueue — Solid Queue's limits_concurrency on LlmJob (key: chat_ID)
    # ensures only one LLM Job runs per chat at a time. If one is running,
    # Solid Queue queues this one and runs it after. D29/D22.
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
git commit -m "feat: heartbeat rule — auto-enqueue LlmJob on new user message"
```

---

## Task 7: Routes and Controller

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
    @agent = Agent.create!(
      name: "chief_of_staff", display_name: "Chief of Staff", status: "idle",
      model_name: "claude-sonnet-4-20250514", system_prompt: "You are CoS.", max_turns: 10
    )
  end

  test "GET /chat shows the chat interface" do
    get chat_path
    assert_response :success
    assert_select "[data-testid='sidebar']"
    assert_select "[data-testid='agent-item']", count: 1
  end

  test "GET /chat/agents/:agent_id shows conversation with agent" do
    chat = Chat.create!(agent: @agent, model_id: @agent.model_name)
    chat.messages.create!(role: "user", content: "Hello")

    get agent_chat_path(@agent)
    assert_response :success
    assert_select "[data-testid='message']", minimum: 1
  end

  test "POST /chat/agents/:agent_id/messages creates message and redirects" do
    assert_enqueued_with(job: LlmJob) do
      post agent_messages_path(@agent), params: { message: { content: "Hello CoS" } }
    end

    assert_response :redirect
    message = Message.last
    assert_equal "user", message.role
    assert_equal "Hello CoS", message.content
  end

  test "POST creates a new chat if none exists for agent" do
    assert_difference "Chat.count", 1 do
      post agent_messages_path(@agent), params: { message: { content: "First message" } }
    end
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
  get "chat", to: "chats#index", as: :chat
  scope "chat" do
    get "agents/:agent_id", to: "chats#show", as: :agent_chat
    post "agents/:agent_id/messages", to: "chats#create_message", as: :agent_messages
  end

  root "chats#index"

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
    if @agent
      @chat = current_chat_for(@agent)
      render :show
    end
  end

  def show
    @chat = current_chat_for(@agent)
  end

  def create_message
    @chat = current_chat_for(@agent) || Chat.create!(agent: @agent, model_id: @agent.model_name)
    @chat.messages.create!(role: "user", content: params[:message][:content])
    redirect_to agent_chat_path(@agent)
  end

  private

  def set_agents
    @agents = Agent.order(:name)
  end

  def set_agent
    @agent = Agent.find(params[:agent_id])
  end

  def current_chat_for(agent)
    agent.chats.order(created_at: :desc).first
  end
end
```

**Step 5: Create view templates (minimal, enough for tests to pass)**

Create these files with minimal content — we'll style them in the next task:

```erb
<!-- app/views/chats/show.html.erb -->
<div class="flex h-screen" data-testid="chat-layout">
  <%= render "sidebar", agents: @agents, current_agent: @agent %>

  <main class="flex-1 flex flex-col">
    <% if @chat %>
      <div data-testid="thread-view" class="flex-1 overflow-y-auto p-4">
        <% @chat.messages.order(:created_at).each do |message| %>
          <div data-testid="message" class="mb-4 <%= message.role == 'user' ? 'text-right' : 'text-left' %>">
            <div class="inline-block max-w-lg px-4 py-2 rounded-lg <%= message.role == 'user' ? 'bg-blue-500 text-white' : 'bg-gray-200 text-gray-900' %>">
              <%= message.content %>
            </div>
          </div>
        <% end %>
      </div>
    <% end %>

    <% if @agent %>
      <div data-testid="compose-bar" class="border-t p-4">
        <%= form_with url: agent_messages_path(@agent), method: :post, class: "flex gap-2" do |f| %>
          <%= f.text_field :content, name: "message[content]", placeholder: "Type a message...",
              class: "flex-1 border rounded-lg px-4 py-2", autofocus: true %>
          <%= f.submit "Send", class: "bg-blue-500 text-white px-4 py-2 rounded-lg cursor-pointer" %>
        <% end %>
      </div>
    <% end %>
  </main>
</div>
```

```erb
<!-- app/views/chats/_sidebar.html.erb -->
<aside data-testid="sidebar" class="w-64 bg-gray-900 text-white flex flex-col">
  <div class="p-4 font-bold text-lg border-b border-gray-700">Daan</div>
  <nav class="flex-1 p-2">
    <% agents.each do |agent| %>
      <%= link_to agent_chat_path(agent),
          class: "flex items-center gap-2 p-2 rounded hover:bg-gray-800 #{agent == current_agent ? 'bg-gray-800' : ''}",
          data: { testid: "agent-item" } do %>
        <span class="w-2 h-2 rounded-full <%= agent.status == 'idle' ? 'bg-green-400' : 'bg-yellow-400' %>"></span>
        <span><%= agent.display_name %></span>
      <% end %>
    <% end %>
  </nav>
</aside>
```

**Step 6: Run tests to verify they pass**

Run: `bin/rails test test/controllers/chats_controller_test.rb`
Expected: All 4 tests PASS.

**Step 7: Commit**

```bash
git add -A
git commit -m "feat: chat UI with routes, controller, and views"
```

---

## Task 8: ViewComponents with Lookbook Previews

Extract the UI into ViewComponents and add Lookbook previews for every visual state. Run `bin/dev` with Lookbook mounted — you should be able to see all component states at `http://localhost:3000/rails/lookbook` without touching the database.

**Files:**
- Create: `app/components/message_component.rb`
- Create: `app/components/message_component.html.erb`
- Create: `app/components/agent_item_component.rb`
- Create: `app/components/agent_item_component.html.erb`
- Create: `app/components/compose_bar_component.rb`
- Create: `app/components/compose_bar_component.html.erb`
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

  test "accepts a Message record" do
    agent = Agent.create!(name: "c_agent", display_name: "CA", status: "idle",
                          model_name: "claude-sonnet-4-20250514", system_prompt: "Test", max_turns: 10)
    chat = Chat.create!(agent: agent, model_id: agent.model_name)
    message = chat.messages.create!(role: "user", content: "From record")

    render_inline(MessageComponent.new(message: message))
    assert_text "From record"
  end
end
```

```ruby
# test/components/agent_item_component_test.rb
require "test_helper"

class AgentItemComponentTest < ViewComponent::TestCase
  test "idle agent shows green dot" do
    agent = Agent.new(name: "cos", display_name: "Chief of Staff", status: "idle",
                      model_name: "m", system_prompt: "p", max_turns: 10)
    render_inline(AgentItemComponent.new(agent: agent))

    assert_selector "[data-testid='agent-item']"
    assert_selector ".bg-green-400"
    assert_text "Chief of Staff"
  end

  test "busy agent shows yellow dot" do
    agent = Agent.new(name: "cos", display_name: "Chief of Staff", status: "busy",
                      model_name: "m", system_prompt: "p", max_turns: 10)
    render_inline(AgentItemComponent.new(agent: agent))

    assert_selector ".bg-yellow-400"
  end

  test "active agent has highlighted background" do
    agent = Agent.new(name: "cos", display_name: "Chief of Staff", status: "idle",
                      model_name: "m", system_prompt: "p", max_turns: 10)
    render_inline(AgentItemComponent.new(agent: agent, active: true))

    assert_selector ".bg-gray-800"
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/components/`
Expected: FAIL — `NameError: uninitialized constant MessageComponent`

**Step 3: Implement MessageComponent**

```ruby
# app/components/message_component.rb
class MessageComponent < ViewComponent::Base
  def initialize(role: nil, content: nil, message: nil)
    if message
      @role = message.role
      @content = message.content
      @dom_id = ActionView::RecordIdentifier.dom_id(message)
    else
      @role = role
      @content = content
      @dom_id = nil
    end
  end

  private

  attr_reader :role, :content, :dom_id

  def alignment_classes
    role == "user" ? "text-right" : "text-left"
  end

  def bubble_classes
    role == "user" ? "bg-blue-500 text-white" : "bg-gray-200 text-gray-900"
  end
end
```

```erb
<%# app/components/message_component.html.erb %>
<div id="<%= dom_id %>"
     data-testid="message"
     data-role="<%= role %>"
     class="mb-4 <%= alignment_classes %>">
  <div class="inline-block max-w-lg px-4 py-2 rounded-lg <%= bubble_classes %>">
    <%= content %>
  </div>
</div>
```

**Step 4: Implement AgentItemComponent**

```ruby
# app/components/agent_item_component.rb
class AgentItemComponent < ViewComponent::Base
  def initialize(agent:, active: false)
    @agent = agent
    @active = active
  end

  private

  attr_reader :agent, :active

  def status_dot_classes
    agent.status == "idle" ? "bg-green-400" : "bg-yellow-400"
  end

  def item_classes
    base = "flex items-center gap-2 p-2 rounded hover:bg-gray-800"
    active ? "#{base} bg-gray-800" : base
  end
end
```

```erb
<%# app/components/agent_item_component.html.erb %>
<%= link_to agent_chat_path(agent),
    id: dom_id(agent),
    class: item_classes,
    data: { testid: "agent-item" } do %>
  <span class="w-2 h-2 rounded-full <%= status_dot_classes %>"></span>
  <span><%= agent.display_name %></span>
<% end %>
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
    <%= f.text_field :content,
        name: "message[content]",
        placeholder: "Message #{agent.display_name}...",
        class: "flex-1 border rounded-lg px-4 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500",
        autofocus: true,
        data: { testid: "message-input" } %>
    <%= f.submit "Send",
        class: "bg-blue-500 hover:bg-blue-600 text-white px-4 py-2 rounded-lg cursor-pointer transition-colors",
        data: { testid: "send-button" } %>
  <% end %>
</div>
```

**Step 6: Write Lookbook previews**

Lookbook previews are classes in `test/components/previews/`. Each `preview` method = one scenario visible in Lookbook.

```ruby
# test/components/previews/message_component_preview.rb
class MessageComponentPreview < ViewComponent::Preview
  # A message from the human user
  def user_message
    render MessageComponent.new(role: "user", content: "Hello, what can you help me with today?")
  end

  # A response from the agent
  def assistant_message
    render MessageComponent.new(role: "assistant", content: "I'm the Chief of Staff. I can help coordinate tasks, answer questions, and delegate work to other agents.")
  end

  # A long message that wraps
  def long_message
    render MessageComponent.new(
      role: "assistant",
      content: "This is a longer response that contains multiple sentences and demonstrates how the message bubble handles text that wraps to multiple lines. The max-width keeps it readable even with verbose content."
    )
  end
end
```

```ruby
# test/components/previews/agent_item_component_preview.rb
class AgentItemComponentPreview < ViewComponent::Preview
  # Agent is idle — green dot
  def idle
    agent = Agent.new(name: "chief_of_staff", display_name: "Chief of Staff",
                      status: "idle", model_name: "m", system_prompt: "p", max_turns: 10)
    render AgentItemComponent.new(agent: agent)
  end

  # Agent is busy working on a task — yellow dot
  def busy
    agent = Agent.new(name: "chief_of_staff", display_name: "Chief of Staff",
                      status: "busy", model_name: "m", system_prompt: "p", max_turns: 10)
    render AgentItemComponent.new(agent: agent)
  end

  # Agent is selected (currently viewed) — highlighted background
  def active
    agent = Agent.new(name: "chief_of_staff", display_name: "Chief of Staff",
                      status: "idle", model_name: "m", system_prompt: "p", max_turns: 10)
    render AgentItemComponent.new(agent: agent, active: true)
  end
end
```

```ruby
# test/components/previews/compose_bar_component_preview.rb
class ComposeBarComponentPreview < ViewComponent::Preview
  # Default compose bar
  def default
    agent = Agent.new(name: "chief_of_staff", display_name: "Chief of Staff",
                      status: "idle", model_name: "m", system_prompt: "p", max_turns: 10)
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
            <%= render MessageComponent.new(message: message) %>
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

**Step 8: Run all component tests to verify they pass**

Run: `bin/rails test test/components/`
Expected: All tests PASS.

**Step 9: Verify Lookbook**

Run: `bin/dev`
Visit: `http://localhost:3000/rails/lookbook`
Expected: Lookbook UI shows three component groups — MessageComponent (3 scenarios), AgentItemComponent (3 scenarios), ComposeBarComponent (1 scenario). Each renders correctly with its Tailwind styles.

**Step 10: Commit**

```bash
git add -A
git commit -m "feat: ViewComponents with Lookbook previews for all UI states"
```

---

## Task 9: Turbo Stream Broadcasts

Push new messages to the browser in real time so the human sees the agent's response appear without refreshing.

**Files:**
- Create: `test/models/message_broadcast_test.rb`
- Modify: `app/models/message.rb`
- Create: `app/views/messages/_message.html.erb`
- Modify: `app/views/chats/show.html.erb`

**Step 1: Write the failing test**

```ruby
# test/models/message_broadcast_test.rb
require "test_helper"

class MessageBroadcastTest < ActiveSupport::TestCase
  setup do
    @agent = Agent.create!(
      name: "broadcast_agent", display_name: "BA", status: "idle",
      model_name: "claude-sonnet-4-20250514", system_prompt: "Test", max_turns: 10
    )
    @chat = Chat.create!(agent: @agent, model_id: @agent.model_name)
  end

  test "message broadcasts to chat stream after create" do
    assert_broadcasts("chat_#{@chat.id}", 1) do
      @chat.messages.create!(role: "assistant", content: "Hello from agent")
    end
  end

  test "user message also broadcasts" do
    # User messages broadcast too (for multi-tab support)
    assert_broadcasts("chat_#{@chat.id}", 1) do
      @chat.messages.create!(role: "user", content: "Hello from human")
    end
  end
end
```

Note: `assert_broadcasts` requires `ActionCable::TestHelper`. You may need to include it in your test helper or use `include ActionCable::TestHelper` in the test class. If this doesn't work with Turbo's broadcast helpers, test the broadcast by checking that the correct Turbo Stream action is generated instead.

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/message_broadcast_test.rb`
Expected: FAIL — no broadcasts happening.

**Step 3: Add broadcast to Message model**

The `MessageComponent` is already built — we broadcast it directly.

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
      renderable: MessageComponent.new(message: self)
    )
  end

  def trigger_heartbeat
    return unless role == "user"
    return if chat.task_status == "in_progress"

    chat.update!(task_status: "pending") if chat.task_status.in?(%w[completed blocked failed])
    LlmJob.perform_later(chat)
  end
end
```

**Step 5: Views are already using `MessageComponent` from Task 8 — nothing to change here.**

**Step 6: Run tests to verify they pass**

Run: `bin/rails test test/models/message_broadcast_test.rb`
Expected: All 2 tests PASS.

**Step 7: Run the full test suite**

Run: `bin/rails test`
Expected: All tests PASS.

**Step 8: Commit**

```bash
git add -A
git commit -m "feat: Turbo Stream broadcasts for live message updates"
```

---

## Task 10: Agent Status Broadcast

Update the sidebar in real time when agent status changes (idle/busy).

**Files:**
- Create: `test/models/agent_status_test.rb`
- Modify: `app/models/agent.rb`
- Create: `app/views/agents/_agent_item.html.erb`
- Modify: `app/views/chats/_sidebar.html.erb`

**Step 1: Write the failing test**

```ruby
# test/models/agent_status_test.rb
require "test_helper"

class AgentStatusTest < ActiveSupport::TestCase
  test "broadcasts to agents stream when status changes" do
    agent = Agent.create!(
      name: "status_agent", display_name: "SA", status: "idle",
      model_name: "claude-sonnet-4-20250514", system_prompt: "Test", max_turns: 10
    )

    assert_broadcasts("agents", 1) do
      agent.update!(status: "busy")
    end
  end

  test "does not broadcast when non-status field changes" do
    agent = Agent.create!(
      name: "status_agent2", display_name: "SA2", status: "idle",
      model_name: "claude-sonnet-4-20250514", system_prompt: "Test", max_turns: 10
    )

    assert_broadcasts("agents", 0) do
      agent.update!(display_name: "Updated Name")
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/agent_status_test.rb`
Expected: FAIL — no broadcasts.

**Step 3: Add broadcast to Agent model**

`AgentItemComponent` is already built in Task 8 — broadcast it directly.

```ruby
# app/models/agent.rb
class Agent < ApplicationRecord
  has_many :chats, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :display_name, presence: true
  validates :model_name, presence: true
  validates :system_prompt, presence: true
  validates :max_turns, presence: true, numericality: { greater_than: 0 }
  validates :status, presence: true, inclusion: { in: %w[idle busy] }

  after_update_commit :broadcast_status, if: :saved_change_to_status?

  private

  def broadcast_status
    broadcast_replace_to(
      "agents",
      target: self,
      renderable: AgentItemComponent.new(agent: self)
    )
  end
end
```

**Step 4: Sidebar already uses `AgentItemComponent` from Task 8 — nothing to change.**

**Step 5: Run tests to verify they pass**

Run: `bin/rails test test/models/agent_status_test.rb`
Expected: All 2 tests PASS.

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: live agent status updates in sidebar via Turbo Stream"
```

---

## Task 10: Seed Data and Smoke Test

Wire everything together: load agents on boot, seed data, and verify the full flow.

**Files:**
- Modify: `db/seeds.rb`
- Create: `config/initializers/daan.rb`
- Create: `test/integration/chat_flow_test.rb`

**Step 1: Write the failing integration test**

```ruby
# test/integration/chat_flow_test.rb
require "test_helper"

class ChatFlowTest < ActionDispatch::IntegrationTest
  setup do
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
  end

  test "full flow: visit chat, send message, job enqueued" do
    agent = Agent.find_by!(name: "chief_of_staff")

    # Visit the chat index
    get chat_path
    assert_response :success
    assert_select "[data-testid='agent-item']", text: /Chief of Staff/

    # Send a message
    assert_enqueued_with(job: LlmJob) do
      post agent_messages_path(agent), params: { message: { content: "Hello CoS!" } }
    end

    # Verify message was created
    chat = agent.chats.last
    assert_equal 1, chat.messages.count
    assert_equal "user", chat.messages.first.role
    assert_equal "Hello CoS!", chat.messages.first.content

    # Follow redirect to see the chat
    follow_redirect!
    assert_response :success
    assert_select "[data-testid='message']", minimum: 1
  end

  test "agent loader creates agent from definition file" do
    agent = Agent.find_by!(name: "chief_of_staff")
    assert_equal "Chief of Staff", agent.display_name
    assert_includes agent.system_prompt, "Chief of Staff"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/integration/chat_flow_test.rb`
Expected: FAIL — agent not found (no initializer running loader yet).

**Step 3: Create initializer**

```ruby
# config/initializers/daan.rb
Rails.application.config.after_initialize do
  if defined?(Rails::Server) || defined?(Rails::Console)
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
  end
end
```

**Step 4: Create seed file**

```ruby
# db/seeds.rb
Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
puts "Loaded #{Agent.count} agent(s): #{Agent.pluck(:name).join(', ')}"
```

**Step 5: Configure RubyLLM initializer**

Edit the generated `config/initializers/ruby_llm.rb`:

```ruby
# config/initializers/ruby_llm.rb
RubyLLM.configure do |config|
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
end
```

**Step 6: Run tests to verify they pass**

Run: `bin/rails test test/integration/chat_flow_test.rb`
Expected: All 2 tests PASS.

**Step 7: Run the full test suite**

Run: `bin/rails test`
Expected: ALL tests PASS.

**Step 8: Commit**

```bash
git add -A
git commit -m "feat: seed data, initializer, and integration smoke test"
```

---

## Task 11: Manual Smoke Test

This is not a code task — it's a verification step.

**Step 1: Set your API key**

```bash
export ANTHROPIC_API_KEY=your-key-here
```

**Step 2: Setup and seed**

```bash
bin/rails db:setup
```

**Step 3: Start the server**

```bash
bin/dev
```

**Step 4: Open the app**

Visit `http://localhost:3000`. You should see:
1. Dark sidebar with "Daan" header and "Chief of Staff" with green dot
2. Empty chat area with compose bar
3. Type "Hello, what can you help me with?" and click Send
4. Your message appears right-aligned
5. After a moment, CoS responds left-aligned
6. Status dot turns yellow (busy) during processing, green (idle) after

**Step 5: Commit any final fixes**

```bash
git add -A
git commit -m "chore: V1 complete — human chats with one agent"
```

---

## Summary

| Task | What | Tests |
|------|------|-------|
| 1 | Add gems, install Tailwind + RubyLLM + Lookbook | — |
| 2 | Agent model | 5 |
| 3 | Extend Chat with agent + task state | 7 |
| 4 | Agent definition loader | 4 |
| 5 | LlmJob (core agentic loop) | 6 |
| 6 | Heartbeat rule on Message | 3 |
| 7 | Routes, controller, views | 4 |
| 8 | ViewComponents + Lookbook previews (all UI states) | 6 |
| 9 | Turbo Stream message broadcasts | 2 |
| 10 | Agent status broadcasts | 2 |
| 11 | Seed, initializer, integration test | 2 |
| 12 | Manual smoke test + Lookbook verification | — |

**Total: 12 tasks, ~41 tests, 11 commits**

**Lookbook:** Visit `http://localhost:3000/rails/lookbook` in development to browse all component states. Component previews live in `test/components/previews/`.
