---
shaping: true
---

# V4: Perspective Switching

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Human can switch to any agent's perspective via a dropdown picker at the top of the sidebar. In agent perspective: sidebar shows only that agent's conversation partners, message inputs are disabled (read-only), message alignment flips so the agent's messages appear right-aligned, and an observability toggle shows/hides tool calls.

**Architecture:** `?perspective=<agent_name>` query param (default: "me" = human). A `Perspective` controller concern reads the param, sets `@perspective_agent` and `@perspective_name`, and overrides `default_url_options` to automatically append `?perspective=<name>` to every URL helper call in the request. No manual perspective threading at link sites — Rails propagates it everywhere for free.

**Not in V4:** Route restructuring to `/:perspective/chat` — query param is equivalent and avoids breaking existing routes.

**Tech Stack:** Rails 8.1, ViewComponent, Turbo, Tailwind, Minitest

---

## Implementation Plan

### Task 1: Perspective concern + controller wiring

`default_url_options` is the key mechanism: by returning `perspective_param` from it, Rails automatically appends `?perspective=<name>` to every URL helper call during the request — path helpers, form actions, redirects, link_to — with no manual threading at any call site.

`before_action` order is critical: `set_perspective` must run before `set_agents` so the sidebar filter can see `@perspective_agent`.

**Files:**
- Create: `app/controllers/concerns/perspective.rb`
- Modify: `app/controllers/chats_controller.rb`
- Modify: `app/controllers/threads_controller.rb`
- Modify: `test/controllers/chats_controller_test.rb`
- Modify: `test/controllers/threads_controller_test.rb`

**Step 1: Write failing tests**

```ruby
# test/controllers/chats_controller_test.rb — add
test "GET /chat/agents/:name with perspective param responds successfully" do
  get chat_agent_path("chief_of_staff"), params: { perspective: "engineering_manager" }
  assert_response :success
end

test "GET /chat/agents/:name with unknown perspective returns 404" do
  get chat_agent_path("chief_of_staff"), params: { perspective: "ghost" }
  assert_response :not_found
end

test "agent links carry perspective param in response" do
  get chat_agent_path("chief_of_staff"), params: { perspective: "engineering_manager" }
  assert_select "a[href*='perspective=engineering_manager']"
end
```

```ruby
# test/controllers/threads_controller_test.rb — add
test "GET /threads/:id with perspective param is successful" do
  Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
  chat = Chat.create!(agent_name: "chief_of_staff")
  get chat_thread_path(chat), params: { perspective: "engineering_manager" }
  assert_response :success
end
```

**Step 2: Run to confirm failures**

```
bin/rails test test/controllers/chats_controller_test.rb \
               test/controllers/threads_controller_test.rb
```

**Step 3: Implement Perspective concern**

`AgentRegistry.find` raises `Daan::AgentNotFoundError` on a miss. `SidebarAgents` already has `rescue_from Daan::AgentNotFoundError, with: :agent_not_found`, so an unknown perspective name automatically returns 404.

```ruby
# app/controllers/concerns/perspective.rb
module Perspective
  extend ActiveSupport::Concern

  included do
    helper_method :perspective_name
  end

  private

  def set_perspective
    name = params[:perspective].presence
    if name && name != "me"
      @perspective_agent = Daan::AgentRegistry.find(name)
      @perspective_name  = name
    else
      @perspective_agent = nil
      @perspective_name  = "me"
    end
  end

  def perspective_name = @perspective_name

  def default_url_options
    perspective_name == "me" ? {} : { perspective: perspective_name }
  end
end
```

**Step 4: Wire into ChatsController — `set_perspective` before `set_agents`**

```ruby
# app/controllers/chats_controller.rb
class ChatsController < ApplicationController
  include SidebarAgents
  include Perspective

  before_action :set_perspective
  before_action :set_agents
  before_action :set_agent, only: :show

  def index
  end

  def show
    @chats = Chat.where(agent_name: @agent.name).order(created_at: :desc).includes(:messages)
  end

  private

  def set_agent
    @agent = Daan::AgentRegistry.find(params[:name])
  end
end
```

**Step 5: Wire into ThreadsController — `set_perspective` before `set_agents`**

```ruby
# app/controllers/threads_controller.rb
class ThreadsController < ApplicationController
  include SidebarAgents
  include Perspective

  before_action :set_perspective, only: :show
  before_action :set_agents, only: :show
  before_action :set_agent_from_params, only: :create
  before_action :set_chat, only: :show

  def show
    @agent      = Daan::AgentRegistry.find(@chat.agent_name)
    @chats      = Chat.where(agent_name: @agent.name).order(created_at: :desc).includes(:messages)
    @hide_tools = params[:show_tools] == "0"
  end

  def create
    @chat = Chat.create!(agent_name: @agent.name)
    Daan::CreateMessage.call(@chat, role: "user", content: message_params[:content])
    redirect_to chat_thread_path(@chat)
  end

  private

  def set_agent_from_params
    @agent = Daan::AgentRegistry.find(params[:agent_name])
  end

  def set_chat
    @chat = Chat.find(params[:id])
  end

  def message_params
    params.require(:message).permit(:content)
  end
end
```

Note: `@hide_tools` is set here — the controller owns param-to-state translation, not the partial.

**Step 6: Run tests**

```
bin/rails test test/controllers/chats_controller_test.rb \
               test/controllers/threads_controller_test.rb
```

Expected: all pass, including the `a[href*='perspective=engineering_manager']` assertion — `default_url_options` makes every link in the rendered response carry the param automatically.

**Step 7: Commit**

```bash
git add app/controllers/concerns/perspective.rb \
        app/controllers/chats_controller.rb \
        app/controllers/threads_controller.rb \
        test/controllers/chats_controller_test.rb \
        test/controllers/threads_controller_test.rb
git commit -m "feat: Perspective concern — default_url_options propagates ?perspective to all URLs automatically"
```

---

### Task 2: Perspective picker partial

A `_perspective_picker.html.erb` partial in the sidebar header. On change it navigates to `GET /chat?perspective=<value>`. No ViewComponent class needed — it's rendered in one place and has no logic worth abstracting.

`perspective_name` is available via `helper_method` — no locals needed.

**Files:**
- Create: `app/views/chats/_perspective_picker.html.erb`
- Modify: `app/views/chats/_sidebar.html.erb`

**Step 1: No new failing unit tests** — the picker is a simple form; coverage comes from the controller integration tests added in Task 1.

**Step 2: Create the partial**

```erb
<%# app/views/chats/_perspective_picker.html.erb %>
<form action="<%= chat_path %>" method="get" class="px-4 py-2">
  <select name="perspective"
          data-testid="perspective-picker"
          onchange="this.form.submit()"
          class="w-full bg-gray-800 text-white text-sm rounded px-2 py-1 border border-gray-600 focus:outline-none focus:ring-1 focus:ring-blue-400">
    <option value="me" <%= "selected" if perspective_name == "me" %>>Me (Human)</option>
    <% @agents.each do |agent| %>
      <option value="<%= agent.name %>" <%= "selected" if perspective_name == agent.name %>>
        <%= agent.display_name %>
      </option>
    <% end %>
  </select>
</form>
```

Note: GET forms replace the query string with only the form fields on submit, so the `action` URL's perspective value (added by `default_url_options`) is overridden by the user's selection. This is correct — the picker is explicitly changing the perspective.

**Step 3: Update sidebar**

```erb
<%# app/views/chats/_sidebar.html.erb %>
<aside data-testid="sidebar" class="w-64 bg-gray-900 text-white flex flex-col">
  <div class="p-4 font-bold text-lg border-b border-gray-700">Daan</div>
  <%= render "chats/perspective_picker" %>
  <%= turbo_stream_from "agents" %>
  <nav class="flex-1 p-2">
    <% agents.each do |agent| %>
      <%= render AgentItemComponent.new(agent: agent, active: agent == current_agent) %>
    <% end %>
  </nav>
</aside>
```

`AgentItemComponent` needs no `perspective:` param — `default_url_options` adds it to `chat_agent_path` automatically inside the component's template.

**Step 4: Commit**

```bash
git add app/views/chats/_perspective_picker.html.erb \
        app/views/chats/_sidebar.html.erb
git commit -m "feat: perspective picker partial in sidebar header"
```

---

### Task 3: Sidebar agent filtering

In non-me perspectives, the sidebar shows only the perspective agent's conversation partners. Logic lives on `Chat` as a class method — `SidebarAgents` calls one method and stays thin.

**Files:**
- Modify: `app/models/chat.rb`
- Modify: `app/controllers/concerns/sidebar_agents.rb`
- Modify: `test/models/chat_test.rb`
- Modify: `test/controllers/chats_controller_test.rb`

**Step 1: Write failing tests**

```ruby
# test/models/chat_test.rb — add
test "conversation_partner_names_for returns agents who delegated to this agent" do
  parent = Chat.create!(agent_name: "chief_of_staff")
  Chat.create!(agent_name: "engineering_manager", parent_chat: parent)
  assert_includes Chat.conversation_partner_names_for("engineering_manager"), "chief_of_staff"
end

test "conversation_partner_names_for returns agents this agent delegated to" do
  parent = Chat.create!(agent_name: "engineering_manager")
  Chat.create!(agent_name: "developer", parent_chat: parent)
  assert_includes Chat.conversation_partner_names_for("engineering_manager"), "developer"
end

test "conversation_partner_names_for returns empty array when no chats" do
  assert_equal [], Chat.conversation_partner_names_for("developer")
end
```

```ruby
# test/controllers/chats_controller_test.rb — add
test "non-me perspective filters sidebar to conversation partners only" do
  parent = Chat.create!(agent_name: "chief_of_staff")
  Chat.create!(agent_name: "engineering_manager", parent_chat: parent)

  get chat_agent_path("engineering_manager"), params: { perspective: "engineering_manager" }
  assert_response :success
  assert_select "[data-testid='agent-item']", count: 1
end
```

**Step 2: Run to confirm failures**

```
bin/rails test test/models/chat_test.rb \
               test/controllers/chats_controller_test.rb
```

**Step 3: Add `Chat.conversation_partner_names_for`**

Uses pure ActiveRecord — no raw SQL strings. Two subqueries: one for upward partners (who delegated to this agent), one for downward partners (who this agent delegated to).

```ruby
# app/models/chat.rb — add class method
def self.conversation_partner_names_for(agent_name)
  my_chats = where(agent_name: agent_name)

  # Agents who delegated TO this agent (parents of this agent's chats)
  parent_names = where(id: my_chats.where.not(parent_chat_id: nil).select(:parent_chat_id))
                   .distinct.pluck(:agent_name)

  # Agents this agent delegated TO (children of this agent's chats)
  child_names = where(parent_chat: my_chats).distinct.pluck(:agent_name)

  (parent_names + child_names).uniq
end
```

**Step 4: Update SidebarAgents**

```ruby
# app/controllers/concerns/sidebar_agents.rb
module SidebarAgents
  extend ActiveSupport::Concern

  included do
    rescue_from Daan::AgentNotFoundError, with: :agent_not_found
  end

  private

  def set_agents
    all = Daan::AgentRegistry.all
    @agents = if @perspective_agent
      partner_names = Chat.conversation_partner_names_for(@perspective_agent.name)
      all.select { |a| partner_names.include?(a.name) }
    else
      all
    end
  end

  def agent_not_found
    head :not_found
  end
end
```

**Step 5: Run tests**

```
bin/rails test test/models/chat_test.rb \
               test/controllers/chats_controller_test.rb
```

Expected: all pass.

**Step 6: Commit**

```bash
git add app/models/chat.rb \
        app/controllers/concerns/sidebar_agents.rb \
        test/models/chat_test.rb \
        test/controllers/chats_controller_test.rb
git commit -m "feat: Chat.conversation_partner_names_for, sidebar filters to partners in agent perspective"
```

---

### Task 4: Read-only compose bar

When in agent perspective, compose bar shows a read-only notice. `perspective_name` is available in partials via `helper_method` — partials use it directly to pass `readonly:`.

**Files:**
- Modify: `app/components/compose_bar_component.rb`
- Modify: `app/components/compose_bar_component.html.erb`
- Modify: `app/views/chats/_dm_view.html.erb`
- Modify: `app/views/threads/_thread_panel.html.erb`
- Create: `test/components/compose_bar_component_test.rb`

**Step 1: Write failing tests**

```ruby
# test/components/compose_bar_component_test.rb
require "test_helper"

class ComposeBarComponentTest < ActiveSupport::TestCase
  include ViewComponent::TestHelpers

  test "renders form when not readonly" do
    render_inline(ComposeBarComponent.new(action: "/messages"))
    assert_includes rendered_content, "data-testid=\"compose-bar\""
    assert_includes rendered_content, "data-testid=\"message-input\""
    assert_includes rendered_content, "data-testid=\"send-button\""
  end

  test "renders read-only notice when readonly" do
    render_inline(ComposeBarComponent.new(action: "/messages", readonly: true))
    assert_includes rendered_content, "data-testid=\"compose-bar\""
    assert_not_includes rendered_content, "data-testid=\"message-input\""
    assert_includes rendered_content, "read-only"
  end
end
```

**Step 2: Run to confirm failures**

```
bin/rails test test/components/compose_bar_component_test.rb
```

**Step 3: Update ComposeBarComponent**

```ruby
# app/components/compose_bar_component.rb
class ComposeBarComponent < ViewComponent::Base
  def initialize(action:, readonly: false)
    @action   = action
    @readonly = readonly
  end

  private

  attr_reader :action, :readonly
end
```

```erb
<%# app/components/compose_bar_component.html.erb %>
<div data-testid="compose-bar" class="border-t p-4">
  <% if readonly %>
    <p class="text-sm text-gray-400 italic text-center">read-only — viewing another agent's perspective</p>
  <% else %>
    <%= form_with url: action, method: :post, class: "flex gap-2" do |f| %>
      <%= f.text_field :content, name: "message[content]",
          placeholder: "Message...",
          class: "flex-1 border rounded-lg px-4 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500",
          autofocus: true,
          required: true,
          data: { testid: "message-input" } %>
      <%= f.submit "Send",
          class: "bg-blue-500 hover:bg-blue-600 text-white px-4 py-2 rounded-lg cursor-pointer",
          data: { testid: "send-button" } %>
    <% end %>
  <% end %>
</div>
```

**Step 4: Update `_dm_view.html.erb` — `perspective_name` available via helper_method**

```erb
<%# app/views/chats/_dm_view.html.erb %>
<div class="flex flex-1 overflow-hidden">
  <div class="<%= open_chat ? 'hidden md:flex' : 'flex' %> flex-col w-full md:w-96 border-r border-gray-200"
       data-testid="thread-list-column">
    <div class="flex-1 overflow-y-auto">
      <% if chats.any? %>
        <ul>
          <% chats.each do |chat| %>
            <%= render ThreadListItemComponent.new(chat: chat) %>
          <% end %>
        </ul>
      <% else %>
        <p class="text-gray-400 text-sm p-4">No conversations yet.</p>
      <% end %>
    </div>
    <%= render ComposeBarComponent.new(action: chat_agent_threads_path(agent),
                                       readonly: perspective_name != "me") %>
  </div>

  <%= turbo_frame_tag "thread_panel",
        class: "#{open_chat ? 'flex' : 'hidden md:flex'} flex-col flex-1 border-l border-gray-200" do %>
    <% if open_chat %>
      <%= render "threads/thread_panel", agent: agent, chat: open_chat %>
    <% end %>
  <% end %>
</div>
```

`ThreadListItemComponent` needs no `perspective:` param — `default_url_options` adds the param to `chat_thread_path` automatically inside its template.

**Step 5: Update `_thread_panel.html.erb`**

```erb
<%# app/views/threads/_thread_panel.html.erb %>
<div data-testid="thread-panel" class="flex flex-col h-full">
  <div class="md:hidden px-4 py-2 border-b border-gray-200">
    <%= link_to "← Back", chat_agent_path(agent), class: "text-sm text-blue-600" %>
  </div>
  <div class="flex-1 overflow-y-auto p-4">
    <%= turbo_stream_from "chat_#{chat.id}" %>
    <div id="messages">
      <% chat_messages = chat.messages.where(visible: true).includes(:tool_calls).order(:created_at) %>
      <% tool_results = chat_messages.select { |m| m.role == "tool" }.index_by(&:tool_call_id).transform_values(&:content) %>
      <% chat_messages.each do |message| %>
        <%= render ChatMessageComponent.new(message: message, results: tool_results) %>
      <% end %>
    </div>
    <div id="typing_indicator"></div>
  </div>
  <%= render ComposeBarComponent.new(action: chat_thread_messages_path(chat),
                                     readonly: perspective_name != "me") %>
</div>
```

The back link `chat_agent_path(agent)` automatically carries `?perspective=` via `default_url_options`.

**Step 6: Run tests**

```
bin/rails test test/components/compose_bar_component_test.rb
```

Expected: all pass.

**Step 7: Commit**

```bash
git add app/components/compose_bar_component.rb \
        app/components/compose_bar_component.html.erb \
        app/views/chats/_dm_view.html.erb \
        app/views/threads/_thread_panel.html.erb \
        test/components/compose_bar_component_test.rb
git commit -m "feat: read-only compose bar in agent perspective"
```

---

### Task 5: Message alignment flip

From an agent's perspective, the agent's own messages (`role: "assistant"`) appear right-aligned with blue bubble. `MessageComponent` gains `viewer_is_agent:` param. The thread panel partial derives `viewer_is_agent` from `perspective_name` and passes it to `ChatMessageComponent`.

**Files:**
- Modify: `app/components/message_component.rb`
- Modify: `app/components/chat_message_component.rb`
- Modify: `app/components/chat_message_component.html.erb`
- Modify: `app/views/threads/_thread_panel.html.erb`
- Modify: `test/components/message_component_test.rb`
- Modify: `test/components/chat_message_component_test.rb`

**Step 1: Write failing tests**

```ruby
# test/components/message_component_test.rb — add
test "assistant message is right-aligned when viewer_is_agent" do
  render_inline(MessageComponent.new(role: "assistant", body: "Done.", viewer_is_agent: true))
  assert_includes rendered_content, "text-right"
  assert_includes rendered_content, "bg-blue-500"
  assert_includes rendered_content, "prose-invert"
end

test "user message is left-aligned when viewer_is_agent" do
  render_inline(MessageComponent.new(role: "user", body: "Do the task.", viewer_is_agent: true))
  assert_includes rendered_content, "text-left"
  assert_includes rendered_content, "bg-gray-200"
end
```

```ruby
# test/components/chat_message_component_test.rb — add
test "flips alignment when viewer_is_agent is true" do
  message = @chat.messages.create!(role: "assistant", content: "Done.")
  render_inline(ChatMessageComponent.new(message: message, viewer_is_agent: true))
  assert_includes rendered_content, "text-right"
  assert_includes rendered_content, "bg-blue-500"
end
```

**Step 2: Run to confirm failures**

```
bin/rails test test/components/message_component_test.rb \
               test/components/chat_message_component_test.rb
```

**Step 3: Update MessageComponent**

```ruby
# app/components/message_component.rb
class MessageComponent < ViewComponent::Base
  RENDERER = Redcarpet::Render::HTML.new(filter_html: true, hard_wrap: true, safe_links_only: true)
  MARKDOWN = Redcarpet::Markdown.new(RENDERER, fenced_code_blocks: true, autolink: true, tables: true)

  def initialize(role:, body:, dom_id: nil, viewer_is_agent: false)
    @role            = role
    @body            = body
    @dom_id          = dom_id
    @viewer_is_agent = viewer_is_agent
  end

  private

  attr_reader :role, :body, :dom_id, :viewer_is_agent

  def self_message?
    viewer_is_agent ? role == "assistant" : role == "user"
  end

  def alignment_classes = self_message? ? "text-right" : "text-left"
  def bubble_classes    = self_message? ? "bg-blue-500 text-white" : "bg-gray-200 text-gray-900"
  def prose_classes     = self_message? ? "prose prose-sm prose-invert" : "prose prose-sm"

  def rendered_body = MARKDOWN.render(body).html_safe
end
```

**Step 4: Update ChatMessageComponent**

```ruby
# app/components/chat_message_component.rb
class ChatMessageComponent < ViewComponent::Base
  def initialize(message:, results: {}, viewer_is_agent: false)
    @message         = message
    @results         = results
    @viewer_is_agent = viewer_is_agent
  end

  private

  attr_reader :message, :results, :viewer_is_agent

  def render?
    message.role != "tool" && message.role != "system"
  end
end
```

```erb
<%# app/components/chat_message_component.html.erb %>
<% if message.tool_calls.any? %>
  <% message.tool_calls.each do |tool_call| %>
    <%= render ToolCallComponent.new(tool_call: tool_call, result: results[tool_call.id]) %>
  <% end %>
  <% if message.content.present? %>
    <%= render MessageComponent.new(role: "assistant", body: message.content,
                                   dom_id: "message_#{message.id}",
                                   viewer_is_agent: viewer_is_agent) %>
  <% end %>
<% else %>
  <%= render MessageComponent.new(role: message.role, body: message.content,
                                 dom_id: "message_#{message.id}",
                                 viewer_is_agent: viewer_is_agent) %>
<% end %>
```

**Step 5: Update `_thread_panel.html.erb` — add `viewer_is_agent`**

```erb
<%# app/views/threads/_thread_panel.html.erb %>
<div data-testid="thread-panel" class="flex flex-col h-full">
  <div class="md:hidden px-4 py-2 border-b border-gray-200">
    <%= link_to "← Back", chat_agent_path(agent), class: "text-sm text-blue-600" %>
  </div>
  <div class="flex-1 overflow-y-auto p-4">
    <%= turbo_stream_from "chat_#{chat.id}" %>
    <div id="messages">
      <% chat_messages = chat.messages.where(visible: true).includes(:tool_calls).order(:created_at) %>
      <% tool_results = chat_messages.select { |m| m.role == "tool" }.index_by(&:tool_call_id).transform_values(&:content) %>
      <% agent_perspective = perspective_name != "me" %>
      <% chat_messages.each do |message| %>
        <%= render ChatMessageComponent.new(message: message, results: tool_results,
                                            viewer_is_agent: agent_perspective) %>
      <% end %>
    </div>
    <div id="typing_indicator"></div>
  </div>
  <%= render ComposeBarComponent.new(action: chat_thread_messages_path(chat),
                                     readonly: agent_perspective) %>
</div>
```

**Step 6: Run tests**

```
bin/rails test test/components/message_component_test.rb \
               test/components/chat_message_component_test.rb
```

**Step 7: Run full test suite**

```
bin/rails test
```

Expected: all pass.

**Step 8: Commit**

```bash
git add app/components/message_component.rb \
        app/components/chat_message_component.rb \
        app/components/chat_message_component.html.erb \
        app/views/threads/_thread_panel.html.erb \
        test/components/message_component_test.rb \
        test/components/chat_message_component_test.rb
git commit -m "feat: message alignment flips in agent perspective — assistant messages right-aligned"
```

---

### Task 6: Observability toggle

A toggle link in the thread panel header hides/shows tool call blocks. `?show_tools=0` to hide (default: show). `@hide_tools` is derived from params in the controller — not in the partial. The toggle link passes `show_tools:` alongside any current params; `default_url_options` adds `?perspective=` automatically.

**Files:**
- Modify: `app/components/chat_message_component.rb`
- Modify: `app/components/chat_message_component.html.erb`
- Modify: `app/views/threads/_thread_panel.html.erb`
- Modify: `test/components/chat_message_component_test.rb`

**Step 1: Write failing tests**

```ruby
# test/components/chat_message_component_test.rb — add
test "hides tool calls when hide_tools is true and message has no text content" do
  message = @chat.messages.create!(role: "assistant", content: nil)
  ToolCall.create!(message: message, tool_call_id: "tc_hide_01", name: "read", arguments: {})
  render_inline(ChatMessageComponent.new(message: message, hide_tools: true))
  assert_not_includes rendered_content, "data-testid=\"tool-call\""
end

test "shows tool calls by default" do
  message = @chat.messages.create!(role: "assistant", content: nil)
  ToolCall.create!(message: message, tool_call_id: "tc_show_01", name: "read", arguments: {})
  render_inline(ChatMessageComponent.new(message: message))
  assert_includes rendered_content, "data-testid=\"tool-call\""
end
```

**Step 2: Run to confirm failures**

```
bin/rails test test/components/chat_message_component_test.rb
```

**Step 3: Update ChatMessageComponent — add `hide_tools:` param**

```ruby
# app/components/chat_message_component.rb
class ChatMessageComponent < ViewComponent::Base
  def initialize(message:, results: {}, viewer_is_agent: false, hide_tools: false)
    @message         = message
    @results         = results
    @viewer_is_agent = viewer_is_agent
    @hide_tools      = hide_tools
  end

  private

  attr_reader :message, :results, :viewer_is_agent, :hide_tools

  def render?
    return false if message.role == "tool" || message.role == "system"
    return false if hide_tools && message.tool_calls.any? && message.content.blank?
    true
  end
end
```

```erb
<%# app/components/chat_message_component.html.erb %>
<% if message.tool_calls.any? %>
  <% unless hide_tools %>
    <% message.tool_calls.each do |tool_call| %>
      <%= render ToolCallComponent.new(tool_call: tool_call, result: results[tool_call.id]) %>
    <% end %>
  <% end %>
  <% if message.content.present? %>
    <%= render MessageComponent.new(role: "assistant", body: message.content,
                                   dom_id: "message_#{message.id}",
                                   viewer_is_agent: viewer_is_agent) %>
  <% end %>
<% else %>
  <%= render MessageComponent.new(role: message.role, body: message.content,
                                 dom_id: "message_#{message.id}",
                                 viewer_is_agent: viewer_is_agent) %>
<% end %>
```

**Step 4: Update `_thread_panel.html.erb` — add toggle link and pass `@hide_tools`**

`default_url_options` adds `?perspective=` automatically to the toggle link. Only `show_tools:` needs to be explicit.

```erb
<%# app/views/threads/_thread_panel.html.erb %>
<div data-testid="thread-panel" class="flex flex-col h-full">
  <div class="flex items-center justify-between px-4 py-2 border-b border-gray-200">
    <div class="md:hidden">
      <%= link_to "← Back", chat_agent_path(agent), class: "text-sm text-blue-600" %>
    </div>
    <%= link_to @hide_tools ? "Show tools" : "Hide tools",
                chat_thread_path(chat, show_tools: @hide_tools ? "1" : "0"),
                class: "text-xs text-gray-500 hover:text-gray-700 ml-auto",
                data: { turbo_frame: "thread_panel" } %>
  </div>
  <div class="flex-1 overflow-y-auto p-4">
    <%= turbo_stream_from "chat_#{chat.id}" %>
    <div id="messages">
      <% chat_messages = chat.messages.where(visible: true).includes(:tool_calls).order(:created_at) %>
      <% tool_results = chat_messages.select { |m| m.role == "tool" }.index_by(&:tool_call_id).transform_values(&:content) %>
      <% agent_perspective = perspective_name != "me" %>
      <% chat_messages.each do |message| %>
        <%= render ChatMessageComponent.new(message: message, results: tool_results,
                                            viewer_is_agent: agent_perspective,
                                            hide_tools: @hide_tools) %>
      <% end %>
    </div>
    <div id="typing_indicator"></div>
  </div>
  <%= render ComposeBarComponent.new(action: chat_thread_messages_path(chat),
                                     readonly: agent_perspective) %>
</div>
```

**Step 5: Run tests**

```
bin/rails test test/components/chat_message_component_test.rb
```

**Step 6: Run full test suite**

```
bin/rails test
```

Expected: all pass.

**Step 7: Commit**

```bash
git add app/components/chat_message_component.rb \
        app/components/chat_message_component.html.erb \
        app/views/threads/_thread_panel.html.erb \
        test/components/chat_message_component_test.rb
git commit -m "feat: observability toggle — hide/show tool calls via ?show_tools=0"
```

---

## Demo Script

1. Start the app: `bin/dev`
2. Send a task to CoS that requires delegation (e.g., "Have the developer read README.md and summarise it")
3. Watch CoS delegate → EM delegate → Developer work → results flow back up
4. Click the **perspective picker** dropdown in the sidebar header — select "Engineering Manager"
5. Sidebar now shows only EM's conversation partners (CoS above, Developer below)
6. Click "Chief of Staff" → see EM's CoS thread. EM's messages (`role: "assistant"`) are **right-aligned** (blue bubble). Task instructions are **left-aligned** (gray). Compose bar shows **read-only** notice.
7. Click **"Hide tools"** — tool call blocks disappear, only text messages remain. URL now has `?perspective=engineering_manager&show_tools=0` — both params carried together automatically.
8. Switch perspective back to **"Me (Human)"** — compose bar re-enables, message alignment reverts, sidebar shows all agents
