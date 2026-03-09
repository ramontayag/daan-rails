---
shaping: true
---

# V2: Agent Uses Tools

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Developer agent uses Read and Write tools to interact with its workspace; tool calls and results appear as collapsible blocks in the thread with a "Typing..." indicator while in flight.

**Architecture:** Tools are `RubyLLM::Tool` subclasses. RubyLLM handles the full tool calling loop automatically within `chat.complete` — when the LLM requests a tool, RubyLLM executes it and continues until a text-only response. Workspace path is injected via `Thread.current[:daan_workspace]` set before `complete` and cleared in `ensure`. After `complete` returns, `ConversationRunner` broadcasts all new messages (tool calls rendered as `ToolCallComponent`, text as `MessageComponent`, tool result messages skipped — rendered inside `ToolCallComponent`). A "Typing..." indicator is broadcast to a dedicated Turbo Stream target at job start and cleared at end.

> **Note on V2.4 (ToolJob):** Deferred. RubyLLM's built-in loop handles tool execution within a single `LlmJob`. Separating into `ToolJob` is the right long-term design (D22) but requires fighting RubyLLM's API. Will be natural to add when delegation (V3) requires it.

> **Note on V2.5 (message_type migration):** Not needed. RubyLLM already structures this: `role: "tool"` messages for results, `tool_calls` association (already in schema) for call records.

**Tech Stack:** RubyLLM 1.13.2 (tool calling), Rails 8.1, Turbo Streams, ViewComponent, Minitest, VCR

---

## Implementation Plan

### Task 1: Developer agent + Agent#tools + AgentLoader

**Files:**
- Create: `lib/daan/core/agents/developer.md`
- Modify: `lib/daan/agent.rb`
- Modify: `lib/daan/agent_loader.rb`
- Modify: `test/lib/daan/agent_loader_test.rb`
- Modify: `test/lib/daan/agent_test.rb`

**Step 1: Write failing tests**

In `test/lib/daan/agent_test.rb`, add:

```ruby
test "tools defaults to empty array when not provided" do
  agent = Daan::Agent.new(
    name: "test", display_name: "Test", model_name: "m",
    system_prompt: "p", max_turns: 5
  )
  assert_equal [], agent.tools
end

test "tools stores the provided array" do
  agent = Daan::Agent.new(
    name: "test", display_name: "Test", model_name: "m",
    system_prompt: "p", max_turns: 5, tools: ["Foo"]
  )
  assert_equal ["Foo"], agent.tools
end
```

In `test/lib/daan/agent_loader_test.rb`, add:

```ruby
test "parse returns empty tools array when not in frontmatter" do
  definition = Daan::AgentLoader.parse(@definitions_path.join("chief_of_staff.md"))
  assert_equal [], definition[:tools]
end
```

**Step 2: Run tests to confirm failure**

```
bin/rails test test/lib/daan/agent_test.rb test/lib/daan/agent_loader_test.rb
```

Expected: failures about unknown keyword `tools` and undefined `definition[:tools]`.

**Step 3: Add `tools` to Agent struct with default**

```ruby
# lib/daan/agent.rb
module Daan
  Agent = Struct.new(:name, :display_name, :model_name, :system_prompt, :max_turns, :tools,
                     keyword_init: true) do
    def initialize(**)
      super
      self.tools ||= []
    end

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

**Step 4: Update AgentLoader to parse tools**

```ruby
# lib/daan/agent_loader.rb
def self.parse(file_path)
  parsed = FrontMatterParser::Parser.parse_file(file_path.to_s)
  fm = parsed.front_matter

  tool_names = fm.fetch("tools", [])
  tools = tool_names.map { |name| Object.const_get(name) }

  {
    name:          fm.fetch("name"),
    display_name:  fm.fetch("display_name"),
    model_name:    fm.fetch("model"),
    max_turns:     fm.fetch("max_turns"),
    system_prompt: parsed.content.strip,
    tools:         tools
  }
rescue => e
  raise "Invalid agent definition at #{file_path}: #{e.message}"
end
```

**Step 5: Create developer.md**

```markdown
---
name: developer
display_name: Developer
model: claude-sonnet-4-20250514
max_turns: 10
tools:
  - Daan::Core::Read
  - Daan::Core::Write
---
You are the Developer on the Daan agent team. You write and modify files in your workspace to accomplish tasks. When asked to read, write, or inspect files, use your tools. Be concise in your responses — show the user what you did, not a wall of text.
```

**Step 6: Add loader test for developer.md**

In `test/lib/daan/agent_loader_test.rb`:

```ruby
test "parse returns tools array for developer agent" do
  definition = Daan::AgentLoader.parse(@definitions_path.join("developer.md"))
  assert_includes definition[:tools], Daan::Core::Read
  assert_includes definition[:tools], Daan::Core::Write
end

test "sync! registers developer agent with tools" do
  Daan::AgentLoader.sync!(@definitions_path)
  agent = Daan::AgentRegistry.find("developer")
  assert_includes agent.tools, Daan::Core::Read
  assert_includes agent.tools, Daan::Core::Write
end
```

**Step 7: Run tests**

```
bin/rails test test/lib/daan/agent_test.rb test/lib/daan/agent_loader_test.rb
```

Expected: all pass.

**Step 8: Commit**

```bash
git add lib/daan/agent.rb lib/daan/agent_loader.rb \
        lib/daan/core/agents/developer.md \
        test/lib/daan/agent_test.rb test/lib/daan/agent_loader_test.rb
git commit -m "feat: add tools field to Agent + developer agent definition"
```

---

### Task 2: Tool base class

**Files:**
- Create: `lib/daan/core/tool.rb`
- Create: `test/lib/daan/core/tool_test.rb`

**Step 1: Write failing test**

```ruby
# test/lib/daan/core/tool_test.rb
require "test_helper"

class Daan::Core::ToolTest < ActiveSupport::TestCase
  setup do
    @workspace = Dir.mktmpdir
    Thread.current[:daan_workspace] = @workspace
  end

  teardown do
    FileUtils.rm_rf(@workspace)
    Thread.current[:daan_workspace] = nil
  end

  test "raises if no workspace set in Thread.current" do
    Thread.current[:daan_workspace] = nil
    # Instantiating a concrete tool subclass should raise
    assert_raises(RuntimeError) { Daan::Core::Read.new }
  end

  test "resolve_path! allows paths within workspace" do
    tool = Daan::Core::Read.new
    # We test this via the Read tool — just check it doesn't raise
    assert_nothing_raised { tool.send(:resolve_path!, "file.txt") }
  end

  test "resolve_path! raises on path traversal" do
    tool = Daan::Core::Read.new
    assert_raises(ArgumentError) { tool.send(:resolve_path!, "../../etc/passwd") }
  end
end
```

**Step 2: Run test to confirm failure**

```
bin/rails test test/lib/daan/core/tool_test.rb
```

Expected: `NameError: uninitialized constant Daan::Core::Tool`

**Step 3: Implement Tool base class**

```ruby
# lib/daan/core/tool.rb
module Daan
  module Core
    class Tool < RubyLLM::Tool
      def initialize
        super
        workspace_path = Thread.current[:daan_workspace]
        raise "No workspace configured. Set Thread.current[:daan_workspace] before calling tools." unless workspace_path
        @workspace = Pathname.new(workspace_path)
      end

      protected

      def resolve_path!(path)
        requested = (@workspace / path).expand_path
        unless requested.to_s.start_with?(@workspace.expand_path.to_s + "/") ||
               requested.to_s == @workspace.expand_path.to_s
          raise ArgumentError, "Path '#{path}' escapes the workspace"
        end
        requested
      end
    end
  end
end
```

**Step 4: Run tests**

```
bin/rails test test/lib/daan/core/tool_test.rb
```

Expected: all pass.

**Step 5: Commit**

```bash
git add lib/daan/core/tool.rb test/lib/daan/core/tool_test.rb
git commit -m "feat: add Daan::Core::Tool base class with workspace scoping"
```

---

### Task 3: Read and Write tools

**Files:**
- Create: `lib/daan/core/read.rb`
- Create: `lib/daan/core/write.rb`
- Create: `test/lib/daan/core/read_test.rb`
- Create: `test/lib/daan/core/write_test.rb`

**Step 1: Write failing Read tests**

```ruby
# test/lib/daan/core/read_test.rb
require "test_helper"

class Daan::Core::ReadTest < ActiveSupport::TestCase
  setup do
    @workspace = Dir.mktmpdir
    Thread.current[:daan_workspace] = @workspace
    File.write(File.join(@workspace, "hello.txt"), "Hello, world!")
  end

  teardown do
    FileUtils.rm_rf(@workspace)
    Thread.current[:daan_workspace] = nil
  end

  test "reads a file within the workspace" do
    tool = Daan::Core::Read.new
    result = tool.execute(path: "hello.txt")
    assert_equal "Hello, world!", result
  end

  test "raises if file does not exist" do
    tool = Daan::Core::Read.new
    assert_raises(RuntimeError) { tool.execute(path: "missing.txt") }
  end

  test "raises on path traversal" do
    tool = Daan::Core::Read.new
    assert_raises(ArgumentError) { tool.execute(path: "../../etc/passwd") }
  end
end
```

**Step 2: Write failing Write tests**

```ruby
# test/lib/daan/core/write_test.rb
require "test_helper"

class Daan::Core::WriteTest < ActiveSupport::TestCase
  setup do
    @workspace = Dir.mktmpdir
    Thread.current[:daan_workspace] = @workspace
  end

  teardown do
    FileUtils.rm_rf(@workspace)
    Thread.current[:daan_workspace] = nil
  end

  test "writes a file to the workspace" do
    tool = Daan::Core::Write.new
    tool.execute(path: "output.txt", content: "Test content")
    assert_equal "Test content", File.read(File.join(@workspace, "output.txt"))
  end

  test "returns a confirmation string" do
    tool = Daan::Core::Write.new
    result = tool.execute(path: "output.txt", content: "Test content")
    assert_includes result, "output.txt"
  end

  test "creates intermediate directories" do
    tool = Daan::Core::Write.new
    tool.execute(path: "subdir/nested.txt", content: "hi")
    assert File.exist?(File.join(@workspace, "subdir", "nested.txt"))
  end

  test "raises on path traversal" do
    tool = Daan::Core::Write.new
    assert_raises(ArgumentError) { tool.execute(path: "../../evil.txt", content: "x") }
  end
end
```

**Step 3: Run to confirm failures**

```
bin/rails test test/lib/daan/core/read_test.rb test/lib/daan/core/write_test.rb
```

**Step 4: Implement Read**

```ruby
# lib/daan/core/read.rb
module Daan
  module Core
    class Read < Tool
      description "Read a file from the workspace"
      param :path, desc: "Relative path to the file within the workspace"

      def execute(path:)
        file = resolve_path!(path)
        raise "File not found: #{path}" unless file.exist?
        file.read
      end
    end
  end
end
```

**Step 5: Implement Write**

```ruby
# lib/daan/core/write.rb
module Daan
  module Core
    class Write < Tool
      description "Write content to a file in the workspace"
      param :path, desc: "Relative path to the file within the workspace"
      param :content, desc: "The content to write"

      def execute(path:, content:)
        file = resolve_path!(path)
        file.dirname.mkpath
        file.write(content)
        "Written #{content.bytesize} bytes to #{path}"
      end
    end
  end
end
```

**Step 6: Run tests**

```
bin/rails test test/lib/daan/core/read_test.rb test/lib/daan/core/write_test.rb
```

Expected: all pass.

**Step 7: Commit**

```bash
git add lib/daan/core/read.rb lib/daan/core/write.rb \
        test/lib/daan/core/read_test.rb test/lib/daan/core/write_test.rb
git commit -m "feat: add Daan::Core::Read and Write tools"
```

---

### Task 4: Update ConversationRunner for tools + workspace

`ConversationRunner` needs to:
1. Capture `last_message_id` before `complete` runs (to find new messages after)
2. Set up the workspace directory and inject via `Thread.current`
3. Pass agent's tools to `with_tools`
4. Replace `broadcast_last_assistant_message` with `broadcast_new_messages` (handles tool call messages and text messages)

**Files:**
- Modify: `lib/daan/conversation_runner.rb`
- Modify: `test/lib/daan/conversation_runner_test.rb`

**Step 1: Update existing tests first**

The existing `with_stub_complete` helper creates no messages during `complete`. Now `broadcast_new_messages` finds messages *newer* than `last_message_id` captured at the start of `call`. Pre-creating the message before `call` means it won't be found (it's older than `last_message_id`). Fix the helper to create the message inside the stub:

```ruby
# test/lib/daan/conversation_runner_test.rb
def with_stub_complete(raise_error: nil, &block)
  called = false
  @chat.define_singleton_method(:complete) do |*|
    called = true
    raise raise_error if raise_error
    messages.create!(role: "assistant", content: "Hello human")
  end
  block.call
  assert called, "expected complete to be called" unless raise_error
ensure
  @chat.singleton_class.remove_method(:complete)
end
```

Also update the broadcast test (no longer pre-creates the message; count is now 3: typing on + message + typing off):

```ruby
test "broadcasts to chat stream: typing on, message, typing off" do
  with_stub_complete do
    assert_broadcasts("chat_#{@chat.id}", 3) do
      Daan::ConversationRunner.call(@chat)
    end
  end
end
```

Remove the old "broadcasts assistant message" test; replace with the above.

**Step 2: Run existing tests to confirm current state**

```
bin/rails test test/lib/daan/conversation_runner_test.rb
```

Note which tests fail — they will be fixed by the implementation.

**Step 3: Implement updated ConversationRunner**

```ruby
# lib/daan/conversation_runner.rb
module Daan
  class ConversationRunner
    def self.call(chat)
      agent = chat.agent
      last_message_id = chat.messages.maximum(:id) || 0

      chat.start!
      chat.broadcast_agent_status
      broadcast_typing(chat, true)

      begin
        if agent.tools.any?
          workspace = Rails.root.join("tmp", "workspaces", agent.name)
          FileUtils.mkdir_p(workspace)
          Thread.current[:daan_workspace] = workspace.to_s
        end

        chat
          .with_model(agent.model_name)
          .with_instructions(agent.system_prompt)
          .with_tools(*agent.tools)
          .complete
      rescue => e
        begin
          chat.fail!
        rescue AASM::InvalidTransition
          # already in a terminal state
        end
        chat.broadcast_agent_status
        broadcast_typing(chat, false)
        raise
      ensure
        Thread.current[:daan_workspace] = nil
      end

      broadcast_new_messages(chat, last_message_id)
      broadcast_typing(chat, false)

      chat.increment!(:turn_count)
      agent.max_turns_reached?(chat.turn_count) ? chat.block! : chat.finish!
      chat.broadcast_agent_status
    end

    def self.broadcast_new_messages(chat, since_id)
      chat.messages
          .includes(:tool_calls)
          .where("messages.id > ?", since_id)
          .order(:id)
          .each do |message|
        next if message.role == "tool"

        if message.tool_calls.any?
          message.tool_calls.each do |tool_call|
            Turbo::StreamsChannel.broadcast_append_to(
              "chat_#{chat.id}",
              target: "messages",
              renderable: ToolCallComponent.new(tool_call: tool_call)
            )
          end
          if message.content.present?
            Turbo::StreamsChannel.broadcast_append_to(
              "chat_#{chat.id}",
              target: "messages",
              renderable: MessageComponent.new(role: "assistant", body: message.content,
                                              dom_id: "message_#{message.id}")
            )
          end
        else
          Turbo::StreamsChannel.broadcast_append_to(
            "chat_#{chat.id}",
            target: "messages",
            renderable: MessageComponent.new(role: message.role, body: message.content,
                                            dom_id: "message_#{message.id}")
          )
        end
      end
    end
    private_class_method :broadcast_new_messages

    def self.broadcast_typing(chat, typing)
      Turbo::StreamsChannel.broadcast_replace_to(
        "chat_#{chat.id}",
        target: "typing_indicator",
        renderable: TypingIndicatorComponent.new(typing: typing)
      )
    end
    private_class_method :broadcast_typing
  end
end
```

**Step 4: Run tests**

```
bin/rails test test/lib/daan/conversation_runner_test.rb
```

Expected: all pass. (TypingIndicatorComponent and ToolCallComponent don't exist yet — tests using `with_stub_complete` that only check state transitions should still pass since they don't trigger the broadcast path through real messages. The broadcast test expects 3 broadcasts which are the typing on/message/typing off.)

> If the broadcast test fails because `TypingIndicatorComponent` is missing, that's expected — it will be fixed in Task 5.

**Step 5: Commit**

```bash
git add lib/daan/conversation_runner.rb test/lib/daan/conversation_runner_test.rb
git commit -m "feat: update ConversationRunner for tools, workspace, and new broadcast"
```

---

### Task 5: Typing indicator

**Files:**
- Create: `app/components/typing_indicator_component.rb`
- Create: `app/components/typing_indicator_component.html.erb`
- Create: `test/components/typing_indicator_component_test.rb`
- Create: `test/components/previews/typing_indicator_component_preview.rb`
- Modify: `app/views/chats/show.html.erb`

**Step 1: Write failing test**

```ruby
# test/components/typing_indicator_component_test.rb
require "test_helper"

class TypingIndicatorComponentTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  test "renders typing text when typing is true" do
    render_inline(TypingIndicatorComponent.new(typing: true))
    assert_includes rendered_content, "Typing"
  end

  test "renders nothing visible when typing is false" do
    render_inline(TypingIndicatorComponent.new(typing: false))
    refute_includes rendered_content, "Typing"
  end
end
```

**Step 2: Run to confirm failure**

```
bin/rails test test/components/typing_indicator_component_test.rb
```

**Step 3: Implement component**

```ruby
# app/components/typing_indicator_component.rb
class TypingIndicatorComponent < ViewComponent::Base
  def initialize(typing:)
    @typing = typing
  end

  private
  attr_reader :typing
end
```

```erb
<%# app/components/typing_indicator_component.html.erb %>
<div id="typing_indicator">
  <% if typing %>
    <p class="text-sm text-gray-400 italic px-4 py-1" data-testid="typing-indicator">Typing...</p>
  <% end %>
</div>
```

**Step 4: Add typing_indicator target to show.html.erb**

Add `<div id="typing_indicator"></div>` after the messages div, inside the thread view:

```erb
<%# app/views/chats/show.html.erb %>
<div class="flex h-screen" data-testid="chat-layout">
  <%= render "sidebar", agents: @agents, current_agent: @agent %>
  <main class="flex-1 flex flex-col overflow-hidden">
    <% if @chat %>
      <div data-testid="thread-view" class="flex-1 overflow-y-auto p-4">
        <%= turbo_stream_from "chat_#{@chat.id}" %>
        <div id="messages">
          <% @chat.messages.where(role: %w[user assistant]).order(:created_at).each do |message| %>
            <%= render MessageComponent.new(role: message.role, body: message.content,
                                           dom_id: "message_#{message.id}") %>
          <% end %>
        </div>
        <div id="typing_indicator"></div>
      </div>
    <% end %>
    <% if @agent %>
      <%= render ComposeBarComponent.new(agent: @agent) %>
    <% end %>
  </main>
</div>
```

**Step 5: Add Lookbook preview**

```ruby
# test/components/previews/typing_indicator_component_preview.rb
class TypingIndicatorComponentPreview < ViewComponent::Preview
  def typing
    render TypingIndicatorComponent.new(typing: true)
  end

  def idle
    render TypingIndicatorComponent.new(typing: false)
  end
end
```

**Step 6: Run tests**

```
bin/rails test test/components/typing_indicator_component_test.rb
bin/rails test test/lib/daan/conversation_runner_test.rb
```

Expected: all pass.

**Step 7: Commit**

```bash
git add app/components/typing_indicator_component.rb \
        app/components/typing_indicator_component.html.erb \
        app/views/chats/show.html.erb \
        test/components/typing_indicator_component_test.rb \
        test/components/previews/typing_indicator_component_preview.rb
git commit -m "feat: add TypingIndicatorComponent and broadcast from ConversationRunner"
```

---

### Task 6: ToolCallComponent + thread view update

**Files:**
- Create: `app/components/tool_call_component.rb`
- Create: `app/components/tool_call_component.html.erb`
- Create: `test/components/tool_call_component_test.rb`
- Create: `test/components/previews/tool_call_component_preview.rb`
- Modify: `app/views/chats/show.html.erb`

**Step 1: Write failing tests**

```ruby
# test/components/tool_call_component_test.rb
require "test_helper"

class ToolCallComponentTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  setup do
    @chat = Chat.create!(agent_name: "chief_of_staff")
    @message = @chat.messages.create!(role: "assistant", content: nil)
    @tool_call = ToolCall.create!(
      message: @message,
      tool_call_id: "tc_001",
      name: "read",
      arguments: { "path" => "hello.txt" }
    )
  end

  test "shows tool name" do
    render_inline(ToolCallComponent.new(tool_call: @tool_call))
    assert_includes rendered_content, "read"
  end

  test "shows arguments" do
    render_inline(ToolCallComponent.new(tool_call: @tool_call))
    assert_includes rendered_content, "hello.txt"
  end

  test "shows result when a tool result message exists" do
    @chat.messages.create!(role: "tool", content: "file contents here",
                           tool_call_id: @tool_call.id)
    render_inline(ToolCallComponent.new(tool_call: @tool_call))
    assert_includes rendered_content, "file contents here"
  end

  test "shows no result when no tool result message exists yet" do
    render_inline(ToolCallComponent.new(tool_call: @tool_call))
    refute_includes rendered_content, "file contents here"
  end
end
```

**Step 2: Run to confirm failure**

```
bin/rails test test/components/tool_call_component_test.rb
```

**Step 3: Implement ToolCallComponent**

```ruby
# app/components/tool_call_component.rb
class ToolCallComponent < ViewComponent::Base
  def initialize(tool_call:)
    @tool_call = tool_call
  end

  private

  attr_reader :tool_call

  def tool_name = tool_call.name
  def arguments = tool_call.arguments
  def result_message = Message.find_by(tool_call_id: tool_call.id)
  def result = result_message&.content
end
```

```erb
<%# app/components/tool_call_component.html.erb %>
<div class="my-1 text-sm font-mono" data-testid="tool-call">
  <details class="bg-gray-100 rounded border border-gray-300">
    <summary class="px-3 py-1 cursor-pointer text-gray-600 select-none">
      <span class="font-semibold text-gray-800"><%= tool_name %></span>
      <span class="text-gray-500">(<%= arguments.map { |k, v| "#{k}: #{v.inspect}" }.join(", ") %>)</span>
    </summary>
    <div class="px-3 py-2 border-t border-gray-300 text-gray-700 whitespace-pre-wrap">
      <% if result %>
        <%= result %>
      <% else %>
        <span class="text-gray-400 italic">running...</span>
      <% end %>
    </div>
  </details>
</div>
```

**Step 4: Update thread view to handle tool messages**

The thread view currently filters to `role: %w[user assistant]`. Update it to render all message types correctly:

```erb
<%# app/views/chats/show.html.erb %>
<div class="flex h-screen" data-testid="chat-layout">
  <%= render "sidebar", agents: @agents, current_agent: @agent %>
  <main class="flex-1 flex flex-col overflow-hidden">
    <% if @chat %>
      <div data-testid="thread-view" class="flex-1 overflow-y-auto p-4">
        <%= turbo_stream_from "chat_#{@chat.id}" %>
        <div id="messages">
          <% @chat.messages.includes(:tool_calls).order(:created_at).each do |message| %>
            <% next if message.role == "tool" %>
            <% if message.tool_calls.any? %>
              <% message.tool_calls.each do |tool_call| %>
                <%= render ToolCallComponent.new(tool_call: tool_call) %>
              <% end %>
              <% if message.content.present? %>
                <%= render MessageComponent.new(role: "assistant", body: message.content,
                                               dom_id: "message_#{message.id}") %>
              <% end %>
            <% else %>
              <%= render MessageComponent.new(role: message.role, body: message.content,
                                             dom_id: "message_#{message.id}") %>
            <% end %>
          <% end %>
        </div>
        <div id="typing_indicator"></div>
      </div>
    <% end %>
    <% if @agent %>
      <%= render ComposeBarComponent.new(agent: @agent) %>
    <% end %>
  </main>
</div>
```

**Step 5: Add Lookbook preview**

```ruby
# test/components/previews/tool_call_component_preview.rb
class ToolCallComponentPreview < ViewComponent::Preview
  def with_result
    chat = Chat.first || Chat.create!(agent_name: "chief_of_staff")
    msg = chat.messages.create!(role: "assistant", content: nil)
    tc = ToolCall.create!(message: msg, tool_call_id: "prev_001", name: "read",
                          arguments: { "path" => "hello.txt" })
    chat.messages.create!(role: "tool", content: "Hello, world!", tool_call_id: tc.id)
    render ToolCallComponent.new(tool_call: tc)
  end

  def running
    chat = Chat.first || Chat.create!(agent_name: "chief_of_staff")
    msg = chat.messages.create!(role: "assistant", content: nil)
    tc = ToolCall.create!(message: msg, tool_call_id: "prev_002", name: "write",
                          arguments: { "path" => "output.txt", "content" => "hello" })
    render ToolCallComponent.new(tool_call: tc)
  end
end
```

**Step 6: Run all tests**

```
bin/rails test test/components/tool_call_component_test.rb
bin/rails test
```

Expected: all pass.

**Step 7: Commit**

```bash
git add app/components/tool_call_component.rb \
        app/components/tool_call_component.html.erb \
        app/views/chats/show.html.erb \
        test/components/tool_call_component_test.rb \
        test/components/previews/tool_call_component_preview.rb
git commit -m "feat: add ToolCallComponent and update thread view to render tool calls"
```

---

### Task 7: VCR integration test for Developer

This records a real API call where the Developer agent uses the Write tool to create a file and then confirms it.

**Files:**
- Modify: `test/jobs/llm_job_test.rb`
- Create: `test/vcr_cassettes/llm_job/developer_write_file.yml` (recorded on first run)

**Step 1: Set up a workspace for the test**

The test needs a tmp workspace that exists during the job and is cleaned up after.

**Step 2: Write the test**

```ruby
# In test/jobs/llm_job_test.rb, add:

class LlmJobTest < ActiveSupport::TestCase
  # ... existing test ...

  test "developer: writes a file using the Write tool" do
    Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
    workspace = Rails.root.join("tmp", "workspaces", "developer")
    FileUtils.mkdir_p(workspace)

    chat = Chat.create!(agent_name: "developer")
    chat.messages.create!(role: "user", content: 'Write "test content" to test.txt')

    VCR.use_cassette("llm_job/developer_write_file") do
      LlmJob.perform_now(chat)
    end

    chat.reload
    assert chat.completed?
    assert chat.messages.joins(:tool_calls).exists?
    assert File.exist?(workspace.join("test.txt"))
  ensure
    FileUtils.rm_rf(workspace.join("test.txt"))
  end
end
```

**Step 3: Record the cassette (run once with real API)**

Delete the cassette file if it exists, then run with `ANTHROPIC_API_KEY` set:

```
bin/rails test test/jobs/llm_job_test.rb
```

This will hit the real Anthropic API and record the cassette. Subsequent runs use the recording.

**Step 4: Commit the cassette + test**

```bash
git add test/jobs/llm_job_test.rb \
        test/vcr_cassettes/llm_job/developer_write_file.yml
git commit -m "test: add VCR integration test for Developer agent using Write tool"
```

---

### Task 8: Run full test suite

```
bin/rails test
```

Expected: all tests pass. If any fail, fix before moving on.

```bash
git add -A  # only if there are fixup changes
git commit -m "fix: address test suite failures in V2"
```

---

# V2: Agent Uses Tools — Slice Detail

The job chain extends beyond a single LLM call. When the LLM returns tool calls, Tool Jobs execute them and post results back, triggering the next LLM Job. Human sees tool calls and results as collapsible blocks in the thread, with a "Typing..." indicator while any job is in flight.

---

## What We Build

| Part | Mechanism | From |
|------|-----------|------|
| **V2.1** | **Tool base** — `Daan::Core::Tool` abstract class with `.description` and `.call(params, workspace:)` interface. Agent frontmatter declares `tools:` list (class names). LlmJob loads tool definitions from the agent's tools list and passes them to RubyLLM. | A4 |
| **V2.2** | **Read + Write tools** — `Daan::Core::Read` reads a file; `Daan::Core::Write` writes content to a path. Both validate that the given path does not escape the provided `workspace:` directory (no path traversal). The workspace location is whatever the agent definition specifies — the tools make no assumptions about where workspaces live. For V2, Developer's workspace is `tmp/workspaces/developer/`, created at first use. | A4 |
| **V2.3** | **Developer agent** — New `lib/daan/core/agents/developer.md` with model, system prompt, `max_turns`, `workspace: directory`, `tools: [Daan::Core::Read, Daan::Core::Write]`. Loaded at boot alongside CoS. Appears in sidebar. Directly chattable. | A2 + A4 |
| **V2.4** | **Tool job chain** — LlmJob: if RubyLLM response contains tool call(s), save each as a `tool_call` Message, enqueue a `ToolJob` per call. ToolJob: instantiate tool, execute with params + workspace path, save result as `tool_result` Message in the same chat. Heartbeat rule (D29) fires on that message → new LlmJob. Per-thread concurrency lock still applies. | A3 |
| **V2.5** | **Tool message types** — Add `message_type` string column to Message (default: "text"; values: "tool_call", "tool_result"). Tool call message stores `{tool_name, params}` JSON in `content`. Tool result message stores output string in `content`. `metadata` on tool_result stores `tool_duration_ms`. | A1 |
| **V2.6** | **Tool block UI + Typing indicator** — `ToolCallComponent`: collapsible block showing tool name + params. Starts in "running..." state when tool_call message is broadcast. Updates in place (Turbo Stream replace) to show result once tool_result message is saved — call and result in one block, expandable. "Typing..." indicator: a broadcast target in the thread view, shown when `task_status → in_progress`, cleared when `completed`/`failed`/`blocked`. Lookbook previews: running, collapsed-with-result, expanded-with-result, typing indicator. | A7 |

---

## Affordances

### UI Affordances

| # | Place | Affordance | Type | Wires Out |
|---|-------|-----------|------|-----------|
| U1 | Sidebar | Developer agent list item | Display | Shows name, status dot (idle/busy) |
| U2 | Thread view | "Typing..." indicator | Display | Shown while LlmJob or ToolJob is in flight; cleared on completion |
| U3 | Thread view | Tool call block (running) | Display | Shows tool name + params; spinner while ToolJob executes |
| U4 | Thread view | Tool call block (done) | Display | Updates in place: shows tool name + params + result; collapsible |
| U5 | Thread view | Message bubble | Display | Agent's final text response (same as V1) |
| U6 | Compose bar | Text input + Send | Action | Creates Message (human), triggers heartbeat |

### Non-UI Affordances

| # | Affordance | Type | Wires Out |
|---|-----------|------|-----------|
| N1 | Developer agent loader | Service | Reads developer.md, registers `Daan::Agent` into registry |
| N2 | Workspace directory setup | `Daan::Core::Tool` base | Ensures workspace directory exists before first tool call |
| N3 | `Daan::Core::Read` | Tool | Reads file at path; validates within provided workspace |
| N4 | `Daan::Core::Write` | Tool | Writes content to path; validates within provided workspace |
| N5 | `ToolJob` | Job | Executes tool, saves tool_result Message, heartbeat fires → new LlmJob |
| N6 | Tool call broadcast | in LlmJob | On tool_call Message save: broadcasts `ToolCallComponent` (running state) to thread |
| N7 | Tool result broadcast | in ToolJob | On tool_result Message save: Turbo Stream replace → updates `ToolCallComponent` in place with result |
| N8 | Typing indicator broadcast | in LlmJob + ToolJob | Broadcast "Typing..." on `in_progress`; broadcast clear on `completed`/`failed`/`blocked` |

---

## Wiring

```
Human types message (U6) → Controller creates Message(role: user)
  → Broadcast user bubble → thread
  → Heartbeat → enqueues LlmJob

LlmJob runs:
  → chat.start! → in_progress
  → N8: broadcast "Typing..." (U2)
  → N1: broadcast AgentItemComponent → sidebar busy dot
  → Load messages + tool definitions from agent
  → Call RubyLLM

  If text-only response:
    → Save Message(role: assistant, message_type: text)
    → Broadcast message bubble → thread (U5)
    → chat.complete!
    → N8: broadcast clear Typing indicator
    → N1: broadcast AgentItemComponent → sidebar idle dot

  If tool call(s) in response:
    → For each tool call:
      → Save Message(role: assistant, message_type: tool_call)
      → N6: broadcast ToolCallComponent (running state) → thread (U3)
      → Enqueue ToolJob

ToolJob runs:
  → Instantiate tool (Read or Write)
  → Execute with params + workspace path
  → Save Message(role: tool, message_type: tool_result, content: output)
  → N7: Turbo Stream replace → ToolCallComponent updates in place (U4)
  → Heartbeat fires on tool_result Message → enqueues new LlmJob

New LlmJob runs (loop continues until text-only response):
  → Context includes all messages including tool results
  → Eventually produces text-only final response → same flow as above
```

---

## What We Defer

- `Bash` tool and any further tools (V3+)
- `DelegateTask`, `ReportBack` (V3)
- Memory tools (V5)
- Cross-workspace access demonstrated in practice (architecture supports it)
- Observability levels toggle (V4)
- Multiple concurrent tool fan-in (D31 — architecture allows it, not demoed)

---

## Demo Script

1. Boot app. Sidebar shows CoS and Developer, both idle.
2. Click Developer. Empty thread.
3. Type: "Create a file called hello.txt with the content 'Hello, world!'"
4. "Typing..." appears. Developer responds: Write tool call block appears (collapsed, "running...").
5. Tool executes. Block updates in place — shows "Write: hello.txt → done" (expandable for full output).
6. Developer sends text: "Done — created hello.txt in my workspace."
7. Type: "Now read it back to me."
8. Read tool call block appears, updates with content. Developer confirms with text showing the content.
