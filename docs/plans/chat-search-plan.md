# Chat Search — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give agents the ability to search across all chat history (their own and other agents') using Slack-like query syntax, and read into specific chats for deeper context.

**Architecture:** Two new tools — `SearchChats` (full-text search via SQLite FTS5 with Slack-style operators) and `ReadChat` (windowed message reader). A migration creates an FTS5 virtual table with SQL triggers to keep it in sync. A query parser extracts operators (`with:`, `from:`, `before:`, `after:`) from free-text search terms.

**Tech Stack:** SQLite FTS5, RubyLLM::Tool, Minitest

---

## File Structure

| File | Responsibility |
|------|---------------|
| `db/migrate/YYYYMMDD_create_messages_fts.rb` | FTS5 virtual table + SQL triggers |
| `lib/daan/core/search_chats.rb` | SearchChats tool — query parsing + FTS5 search + result formatting |
| `lib/daan/core/read_chat.rb` | ReadChat tool — windowed message reader |
| `test/lib/daan/core/search_chats_test.rb` | Tests for SearchChats |
| `test/lib/daan/core/read_chat_test.rb` | Tests for ReadChat |

---

### Task 1: FTS5 Migration

**Files:**
- Create: `db/migrate/YYYYMMDD_create_messages_fts.rb`

- [ ] **Step 1: Generate the migration**

Run:
```bash
cd /home/ramon/src/me/daan-rails/.worktrees/feat-chat-search
bin/rails generate migration CreateMessagesFts
```

- [ ] **Step 2: Write the migration with FTS5 virtual table and triggers**

Replace the generated migration content with:

```ruby
class CreateMessagesFts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE VIRTUAL TABLE messages_fts USING fts5(
        content,
        content='messages',
        content_rowid='id'
      );
    SQL

    # Trigger: insert into FTS when a user/assistant message is created
    execute <<~SQL
      CREATE TRIGGER messages_fts_ai AFTER INSERT ON messages
      WHEN new.role IN ('user', 'assistant')
      BEGIN
        INSERT INTO messages_fts(rowid, content) VALUES (new.id, new.content);
      END;
    SQL

    # Trigger: remove from FTS when a message is deleted
    execute <<~SQL
      CREATE TRIGGER messages_fts_ad AFTER DELETE ON messages
      WHEN old.role IN ('user', 'assistant')
      BEGIN
        INSERT INTO messages_fts(messages_fts, rowid, content) VALUES ('delete', old.id, old.content);
      END;
    SQL

    # Trigger: update FTS when message content changes
    execute <<~SQL
      CREATE TRIGGER messages_fts_au AFTER UPDATE OF content ON messages
      WHEN new.role IN ('user', 'assistant')
      BEGIN
        INSERT INTO messages_fts(messages_fts, rowid, content) VALUES ('delete', old.id, old.content);
        INSERT INTO messages_fts(rowid, content) VALUES (new.id, new.content);
      END;
    SQL

    # Backfill existing messages into FTS index
    execute <<~SQL
      INSERT INTO messages_fts(rowid, content)
      SELECT id, content FROM messages WHERE role IN ('user', 'assistant');
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS messages_fts_au"
    execute "DROP TRIGGER IF EXISTS messages_fts_ad"
    execute "DROP TRIGGER IF EXISTS messages_fts_ai"
    execute "DROP TABLE IF EXISTS messages_fts"
  end
end
```

- [ ] **Step 3: Run the migration**

Run:
```bash
bin/rails db:migrate
```

Expected: Migration runs successfully. `db/schema.rb` won't show the virtual table (Rails doesn't dump FTS5 tables), but it exists in SQLite.

- [ ] **Step 4: Verify FTS5 works**

Run:
```bash
bin/rails runner "
  chat = Chat.create!(agent_name: 'test')
  chat.messages.create!(role: 'user', content: 'Have we discussed the authentication system before?')
  chat.messages.create!(role: 'assistant', content: 'I do not recall any prior discussion about authentication.')
  chat.messages.create!(role: 'tool', content: 'tool result noise')

  results = ActiveRecord::Base.connection.execute(\"SELECT rowid FROM messages_fts WHERE messages_fts MATCH 'authentication'\")
  puts \"FTS matches: #{results.length}\"
  puts \"Expected: 2 (user + assistant, not tool)\"

  Chat.find(chat.id).destroy
"
```

Expected: `FTS matches: 2`

- [ ] **Step 5: Commit**

```bash
git add db/migrate/*_create_messages_fts.rb
git commit -m "feat: add FTS5 virtual table for message full-text search

SQL triggers keep the index in sync on insert/update/delete.
Only indexes user and assistant messages (skips tool messages).
Backfills existing messages."
```

---

### Task 2: SearchChats Tool

**Files:**
- Create: `test/lib/daan/core/search_chats_test.rb`
- Create: `lib/daan/core/search_chats.rb`

- [ ] **Step 1: Write the failing tests**

Create `test/lib/daan/core/search_chats_test.rb`:

```ruby
require "test_helper"

class Daan::Core::SearchChatsTest < ActiveSupport::TestCase
  setup do
    # Use newly merged build_agent helper for DRY test setup
    Daan::Core::AgentRegistry.register(
      Daan::Core::Agent.new(name: "developer", display_name: "Developer",
                      model_name: "m", system_prompt: "p", max_steps: 10)
    )
    Daan::Core::AgentRegistry.register(
      Daan::Core::Agent.new(name: "chief_of_staff", display_name: "Chief of Staff",
                      model_name: "m", system_prompt: "p", max_steps: 10,
                      delegates_to: ["developer"])
    )

    @dev_chat = Chat.create!(agent_name: "developer")
    @dev_chat.messages.create!(role: "user", content: "Please fix the authentication bug in the login controller")
    @dev_chat.messages.create!(role: "assistant", content: "I found the authentication issue and fixed it")

    @cos_chat = Chat.create!(agent_name: "chief_of_staff")
    @cos_chat.messages.create!(role: "user", content: "What is the status of the deployment pipeline?")
    @cos_chat.messages.create!(role: "assistant", content: "The deployment pipeline is running smoothly")

    # Delegation sub-chat: CoS delegated to developer
    @sub_chat = Chat.create!(agent_name: "developer", parent_chat: @cos_chat)
    @sub_chat.messages.create!(role: "user", content: "Handle the database migration for authentication")
    @sub_chat.messages.create!(role: "assistant", content: "Migration completed successfully")

    @tool = Daan::Core::SearchChats.new
  end

  test "searches across all chats by free text" do
    result = @tool.execute(query: "authentication")
    assert_includes result, "authentication bug"
    assert_includes result, "authentication issue"
    assert_includes result, "database migration for authentication"
  end

  test "returns no results message when nothing matches" do
    result = @tool.execute(query: "zxynonexistent")
    assert_includes result, "No results"
  end

  test "filters with:agent_name to chats where agent is owner" do
    result = @tool.execute(query: "with:chief_of_staff pipeline")
    assert_includes result, "deployment pipeline"
    refute_includes result, "authentication bug"
  end

  test "filters with:agent_name includes chats where agent is delegator" do
    result = @tool.execute(query: "with:chief_of_staff migration")
    assert_includes result, "database migration"
  end

  test "filters with:user to top-level chats only" do
    result = @tool.execute(query: "with:user authentication")
    assert_includes result, "authentication bug"
    refute_includes result, "database migration"
  end

  test "filters from:user to user-role messages" do
    result = @tool.execute(query: "from:user authentication")
    assert_includes result, "fix the authentication bug"
    refute_includes result, "authentication issue and fixed"
  end

  test "filters from:agent_name to assistant messages in that agent's chats" do
    result = @tool.execute(query: "from:developer authentication")
    assert_includes result, "authentication issue and fixed"
    refute_includes result, "fix the authentication bug"
  end

  test "filters before:date" do
    @dev_chat.messages.first.update!(created_at: 3.days.ago)
    @dev_chat.messages.last.update!(created_at: 3.days.ago)
    @cos_chat.messages.first.update!(created_at: 1.day.from_now)

    result = @tool.execute(query: "before:#{Date.yesterday.iso8601} authentication")
    assert_includes result, "authentication bug"
    refute_includes result, "deployment pipeline"
  end

  test "filters after:date" do
    @dev_chat.messages.first.update!(created_at: 3.days.ago)
    @dev_chat.messages.last.update!(created_at: 3.days.ago)

    result = @tool.execute(query: "after:#{Date.yesterday.iso8601} pipeline")
    assert_includes result, "deployment pipeline"
    refute_includes result, "authentication"
  end

  test "includes surrounding messages for context" do
    result = @tool.execute(query: "authentication issue")
    # The matching assistant message should have the preceding user message as context
    assert_includes result, "fix the authentication bug"
  end

  test "includes chat metadata in results" do
    result = @tool.execute(query: "authentication bug")
    assert_includes result, "developer"
    assert_includes result, "Chat ##{@dev_chat.id}"
  end

  test "limits results to 10" do
    15.times do |i|
      chat = Chat.create!(agent_name: "developer")
      chat.messages.create!(role: "user", content: "unique_search_term iteration #{i}")
    end

    result = @tool.execute(query: "unique_search_term")
    assert_operator result.scan(/Chat #/).length, :<=, 10
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
cd /home/ramon/src/me/daan-rails/.worktrees/feat-chat-search
bin/rails test test/lib/daan/core/search_chats_test.rb
```

Expected: FAIL — `Daan::Core::SearchChats` doesn't exist yet.

- [ ] **Step 3: Implement SearchChats**

Create `lib/daan/core/search_chats.rb`:

```ruby
module Daan
  module Core
    class SearchChats < RubyLLM::Tool
      include Daan::Core::Tool.module(timeout: 10.seconds)

      description "Search across all chat history using Slack-like query syntax. " \
                  "Operators: with:agent_name (chats involving that agent), with:user (chats with human), " \
                  "from:user (human messages), from:agent_name (that agent's responses), " \
                  "before:YYYY-MM-DD, after:YYYY-MM-DD. Everything else is free-text search."
      param :query, desc: "Search query with optional operators (e.g. 'authentication with:developer after:2026-01-01')"

      RESULT_LIMIT = 10
      CONTEXT_WINDOW = 2

      def initialize(workspace: nil, chat: nil, storage: nil, agent_name: nil)
      end

      def execute(query:)
        operators, search_terms = parse_query(query)
        return "Error: no search terms provided. Include at least one word to search for." if search_terms.blank?

        message_ids = fts_search(search_terms)
        return "No results found for: #{search_terms}" if message_ids.empty?

        messages = Message.where(id: message_ids).includes(:chat)
        messages = apply_filters(messages, operators)
        messages = messages.order(created_at: :desc).limit(RESULT_LIMIT)

        return "No results found for: #{query}" if messages.empty?

        format_results(messages)
      end

      private

      def parse_query(query)
        operators = {}
        terms = []

        query.split(/\s+/).each do |token|
          case token
          when /\Awith:(.+)\z/
            (operators[:with] ||= []) << $1
          when /\Afrom:(.+)\z/
            (operators[:from] ||= []) << $1
          when /\Abefore:(.+)\z/
            operators[:before] = Date.parse($1)
          when /\Aafter:(.+)\z/
            operators[:after] = Date.parse($1)
          else
            terms << token
          end
        end

        [operators, terms.join(" ")]
      end

      def fts_search(terms)
        escaped = terms.split(/\s+/).map { |t| %("#{t}") }.join(" ")
        rows = ActiveRecord::Base.connection.execute(
          "SELECT rowid FROM messages_fts WHERE messages_fts MATCH '#{ActiveRecord::Base.connection.quote_string(escaped)}'"
        )
        rows.map { |r| r["rowid"] }
      end

      def apply_filters(messages, operators)
        if operators[:with]
          chat_ids = chat_ids_for_with(operators[:with])
          messages = messages.where(chat_id: chat_ids) if chat_ids
        end

        if operators[:from]
          messages = apply_from_filter(messages, operators[:from])
        end

        if operators[:before]
          messages = messages.where(Message.arel_table[:created_at].lt(operators[:before].beginning_of_day))
        end

        if operators[:after]
          messages = messages.where(Message.arel_table[:created_at].gt(operators[:after].end_of_day))
        end

        messages
      end

      def chat_ids_for_with(names)
        ids = Set.new
        names.each do |name|
          if name == "user"
            # Top-level chats (human involved) = chats with no parent
            ids.merge(Chat.where(parent_chat_id: nil).pluck(:id))
          else
            # Chats where this agent is the owner
            ids.merge(Chat.where(agent_name: name).pluck(:id))
            # Chats where this agent is the delegator (parent)
            ids.merge(Chat.where(parent_chat: Chat.where(agent_name: name)).pluck(:id))
          end
        end
        ids
      end

      def apply_from_filter(messages, names)
        conditions = names.map do |name|
          if name == "user"
            Message.arel_table[:role].eq("user")
          else
            Message.arel_table[:role].eq("assistant")
              .and(Message.arel_table[:chat_id].in(
                Chat.where(agent_name: name).select(:id).arel
              ))
          end
        end

        combined = conditions.reduce { |a, b| a.or(b) }
        messages.where(combined)
      end

      def format_results(messages)
        messages.map { |msg| format_one(msg) }.join("\n\n---\n\n")
      end

      def format_one(msg)
        chat = msg.chat
        header = "Chat ##{chat.id} (#{chat.agent_name}, #{chat.task_status}) — #{msg.created_at.strftime('%Y-%m-%d %H:%M')}"

        surrounding = chat.messages
          .where(role: %w[user assistant])
          .where(Message.arel_table[:id].gteq(msg.id - CONTEXT_WINDOW))
          .where(Message.arel_table[:id].lteq(msg.id + CONTEXT_WINDOW))
          .order(:id)

        context_lines = surrounding.map do |m|
          prefix = m.id == msg.id ? ">> " : "   "
          "#{prefix}[#{m.role}] #{m.content.to_s.truncate(200)}"
        end

        "#{header}\n#{context_lines.join("\n")}"
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
bin/rails test test/lib/daan/core/search_chats_test.rb
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/daan/core/search_chats.rb test/lib/daan/core/search_chats_test.rb
git commit -m "feat: add SearchChats tool with Slack-like query syntax

Supports operators: with:, from:, before:, after: mixed with free-text.
Uses FTS5 for full-text search. Returns top 10 results with surrounding
message context."
```

---

### Task 3: ReadChat Tool

**Files:**
- Create: `test/lib/daan/core/read_chat_test.rb`
- Create: `lib/daan/core/read_chat.rb`

- [ ] **Step 1: Write the failing tests**

Create `test/lib/daan/core/read_chat_test.rb`:

```ruby
require "test_helper"

class Daan::Core::ReadChatTest < ActiveSupport::TestCase
  setup do
    Daan::Core::AgentRegistry.register(
      # same, use build_agent
      Daan::Core::Agent.new(name: "developer", display_name: "Developer",
                      model_name: "m", system_prompt: "p", max_steps: 10)
    )
    @chat = Chat.create!(agent_name: "developer")
    25.times do |i|
      role = i.even? ? "user" : "assistant"
      @chat.messages.create!(role: role, content: "Message number #{i}")
    end
    @tool = Daan::Core::ReadChat.new
  end

  test "reads messages from a chat with default limit" do
    result = @tool.execute(chat_id: @chat.id)
    assert_includes result, "Message number 0"
    assert_includes result, "Message number 19"
    refute_includes result, "Message number 20"
  end

  test "respects offset parameter" do
    result = @tool.execute(chat_id: @chat.id, offset: 10)
    refute_includes result, "Message number 0"
    assert_includes result, "Message number 10"
  end

  test "respects limit parameter" do
    result = @tool.execute(chat_id: @chat.id, limit: 5)
    assert_includes result, "Message number 0"
    assert_includes result, "Message number 4"
    refute_includes result, "Message number 5"
  end

  test "includes chat metadata in header" do
    result = @tool.execute(chat_id: @chat.id)
    assert_includes result, "Chat ##{@chat.id}"
    assert_includes result, "developer"
    assert_includes result, "pending"
  end

  test "only shows user and assistant messages" do
    @chat.messages.create!(role: "tool", content: "tool noise")
    result = @tool.execute(chat_id: @chat.id, limit: 100)
    refute_includes result, "tool noise"
  end

  test "returns error for nonexistent chat" do
    result = @tool.execute(chat_id: 999999)
    assert_includes result, "not found"
  end

  test "shows total message count and current window" do
    result = @tool.execute(chat_id: @chat.id, limit: 5)
    assert_includes result, "25 messages"
    assert_includes result, "showing 1-5"
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
bin/rails test test/lib/daan/core/read_chat_test.rb
```

Expected: FAIL — `Daan::Core::ReadChat` doesn't exist yet.

- [ ] **Step 3: Implement ReadChat**

Create `lib/daan/core/read_chat.rb`:

```ruby
module Daan
  module Core
    class ReadChat < RubyLLM::Tool
      include Daan::Core::Tool.module(timeout: 10.seconds)

      description "Read messages from a specific chat. Use after SearchChats to dive deeper " \
                  "into a conversation. Returns user and assistant messages only (no tool internals)."
      param :chat_id, desc: "ID of the chat to read"
      param :offset, desc: "Number of messages to skip (default: 0)", required: false
      param :limit, desc: "Number of messages to return (default: 20, max: 50)", required: false

      DEFAULT_LIMIT = 20
      MAX_LIMIT = 50

      def initialize(workspace: nil, chat: nil, storage: nil, agent_name: nil)
      end

      def execute(chat_id:, offset: 0, limit: DEFAULT_LIMIT)
        chat = Chat.find_by(id: chat_id)
        return "Error: Chat ##{chat_id} not found." unless chat

        offset = [offset.to_i, 0].max
        limit = [[limit.to_i, 1].max, MAX_LIMIT].min

        all_messages = chat.messages.where(role: %w[user assistant]).order(:id)
        total = all_messages.count
        window = all_messages.offset(offset).limit(limit)

        header = "Chat ##{chat.id} (#{chat.agent_name}, #{chat.task_status}) — " \
                 "#{total} messages, showing #{offset + 1}-#{[offset + limit, total].min}"

        lines = window.map do |msg|
          "[#{msg.created_at.strftime('%Y-%m-%d %H:%M')}] [#{msg.role}] #{msg.content}"
        end

        "#{header}\n\n#{lines.join("\n\n")}"
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
bin/rails test test/lib/daan/core/read_chat_test.rb
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/daan/core/read_chat.rb test/lib/daan/core/read_chat_test.rb
git commit -m "feat: add ReadChat tool for windowed message reading

Allows agents to read a specific chat's messages with offset/limit.
Only returns user and assistant messages. Companion to SearchChats
for drilling into search results."
```

---

### Task 4: Wire Up Tools to Agents

**Files:**
- Modify: `lib/daan/core/agents/chief_of_staff.md`
- Modify: `lib/daan/core/agents/engineering_manager.md`
- Modify: `lib/daan/core/agents/developer.md`

- [ ] **Step 1: Add SearchChats and ReadChat to all agent definitions**

Add these two lines to the `tools:` array in each agent definition file:

```yaml
  - Daan::Core::SearchChats
  - Daan::Core::ReadChat
```

Add to:
- `lib/daan/core/agents/chief_of_staff.md`
- `lib/daan/core/agents/engineering_manager.md`
- `lib/daan/core/agents/developer.md`

And any other agent definition files that should have search capability.

- [ ] **Step 2: Run the full test suite**

Run:
```bash
bin/rails test && bin/rails test:system
```

Expected: All tests pass (existing + new).

- [ ] **Step 3: Commit**

```bash
git add lib/daan/core/agents/
git commit -m "feat: add SearchChats and ReadChat to all agent tool lists"
```

---

### Task 5: Update Shaping Docs

**Files:**
- Modify: `docs/shaping.md`
- Modify: `docs/slices.md`

- [ ] **Step 1: Add Chat Search slice to slices.md**

Add a new slice entry to the Slice Overview table and a section pointing to this plan.

- [ ] **Step 2: Update shaping.md if needed**

Add any new decisions (D-numbers) to the shaping doc if this feature revealed new architectural decisions.

- [ ] **Step 3: Commit**

```bash
git add docs/shaping.md docs/slices.md
git commit -m "docs: add Chat Search slice to shaping and slices docs"
```
