---
shaping: true
---

# Slice 1: Single-step execution (`chat.step`)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace `chat.complete` (the looping agentic call) with `chat.step` (one LLM call + tool execution, no recursion). `LlmJob` re-enqueues itself when the response contains tool calls. `BroadcastMessagesJob` is removed — the response is broadcast inline after each step.

From the user's perspective, agents behave identically. Under the hood: each LLM call is a separate job.

**Shaping:** `docs/shaping-chat-step.md` (Shape A, Slice 1)
**Slices:** `docs/slices-chat-step.md`

**Architecture:**
- `Chat#step` — added to a fork of `ruby_llm` on GitHub (`ramontayag/ruby_llm`), installed via `gem "ruby_llm", github: "ramontayag/ruby_llm", branch: "feat/chat-step"` in the Gemfile. Makes one provider call, executes any tool calls, returns the response without recursing. Same internal logic as `complete` + `handle_tool_calls` minus the final `complete(&)` recursive call. A monkey-patch initializer is acceptable as a temporary measure but the fork is preferred.
- `ConversationRunner#run_step` — replaces `run_llm`. Calls `chat.step`, broadcasts the response inline.
- `ConversationRunner#finish_or_reenqueue` — after a step, if `response.tool_call?` re-enqueues `LlmJob`; otherwise calls `finish_conversation`. Typing indicator stays on when re-enqueueing (turns off only on final response or error).
- `BroadcastMessagesJob` — deleted. `broadcast_new_messages` becomes a private helper used only inline in `run_step`.

**Not in this slice:** `max_steps` enforcement, `step_count`, `turn_count` migration (Slice 2).

**Tech Stack:** Rails 8.1, Minitest, RubyLLM 1.13.2

---

## Implementation Plan

### Task 1: Fork ruby_llm and add `Chat#step`

`step` becomes the primitive: one provider call + tool execution, no recursion. `complete` is refactored to call `step` and recurse only if tool calls were returned. `handle_tool_calls` is removed — its logic moves into `step`.

**Pre-requisite:** Fork `https://github.com/crmne/ruby_llm` to `ramontayag/ruby_llm` on GitHub, then clone it locally to add the method.

**Files (in the ruby_llm fork):**
- Modify: `lib/ruby_llm/chat.rb` — add `Chat#step`, refactor `complete` to call it, remove `handle_tool_calls`

**Files (in daan-rails):**
- Modify: `Gemfile` — point `ruby_llm` at the fork
- Create: `test/lib/ruby_llm/chat_step_test.rb`

**Step 1: Write failing tests**

```ruby
# test/lib/ruby_llm/chat_step_test.rb
require "test_helper"

class RubyLlmChatStepTest < ActiveSupport::TestCase
  ToolCallDouble = Struct.new(:id, :name, :arguments)

  def stub_response(tool_call: false, content: "done")
    tool_calls = tool_call ? { tc_1: ToolCallDouble.new("tc_1", "test_tool", {}) } : {}
    OpenStruct.new("tool_call?" => tool_call, content: content, role: :assistant, tool_calls: tool_calls)
  end

  test "step returns the response without recursing" do
    chat = RubyLLM::Chat.new(model: "claude-haiku-4-5-20251001", assume_model_exists: true,
                              provider: :anthropic)
    step_count = 0
    chat.stub(:step, -> {
      step_count += 1
      stub_response(tool_call: false)
    }) do
      chat.step
    end
    assert_equal 1, step_count
  end

  test "step does not call itself recursively when tool calls are returned" do
    chat = RubyLLM::Chat.new(model: "claude-haiku-4-5-20251001", assume_model_exists: true,
                              provider: :anthropic)
    call_count = 0
    # Stub the provider directly so tool execution doesn't actually run
    chat.instance_variable_get(:@provider).stub(:complete, -> (*_) {
      call_count += 1
      stub_response(tool_call: true)
    }) do
      chat.step rescue nil
    end
    assert_equal 1, call_count, "step must make exactly one provider call"
  end

  test "complete recurses by calling step until no tool calls" do
    chat = RubyLLM::Chat.new(model: "claude-haiku-4-5-20251001", assume_model_exists: true,
                              provider: :anthropic)
    step_count = 0
    responses = [stub_response(tool_call: true), stub_response(tool_call: false)]
    chat.stub(:step, -> {
      step_count += 1
      responses.shift || stub_response(tool_call: false)
    }) do
      chat.complete rescue nil
    end
    assert_equal 2, step_count, "complete must keep calling step until no tool calls"
  end
end
```

**Step 2: Run to confirm failures**

```
bin/rails test test/lib/ruby_llm/chat_step_test.rb
```

**Step 3: Add `Chat#step` to the fork and refactor `complete`**

In the `ruby_llm` fork, open `lib/ruby_llm/chat.rb`:

1. Add `step` as a public method containing the provider call + tool execution logic currently split between `complete` and `handle_tool_calls`:

```ruby
# Like complete, but makes exactly one provider call.
# Executes any tool calls returned, then stops — does NOT recurse.
# Returns the response so the caller can decide whether to continue.
def step(&)
  response = @provider.complete(
    messages,
    tools: @tools,
    tool_prefs: @tool_prefs,
    temperature: @temperature,
    model: @model,
    params: @params,
    headers: @headers,
    schema: @schema,
    thinking: @thinking,
    &wrap_streaming_block(&)
  )

  @on[:new_message]&.call unless block_given?
  add_message response
  @on[:end_message]&.call(response)

  if response.tool_call?
    response.tool_calls.each_value do |tool_call|
      @on[:new_message]&.call
      @on[:tool_call]&.call(tool_call)
      result = execute_tool(tool_call)
      @on[:tool_result]&.call(result)
      tool_payload = result.is_a?(Tool::Halt) ? result.content : result
      content = content_like?(tool_payload) ? tool_payload : tool_payload.to_s
      message = add_message(role: :tool, content:, tool_call_id: tool_call.id)
      @on[:end_message]&.call(message)
    end
    reset_tool_choice if forced_tool_choice?
  end

  response
end
```

2. Refactor `complete` to delegate to `step`:

```ruby
def complete(&)
  response = step(&)
  response.tool_call? ? complete(&) : response
end
```

3. Remove `handle_tool_calls` entirely — its logic now lives in `step`.

Commit and push to the `feat/chat-step` branch on `ramontayag/ruby_llm`.

Then update `Gemfile` in daan-rails:

```ruby
gem "ruby_llm", github: "ramontayag/ruby_llm", branch: "feat/chat-step"
```

Run `bundle install` after updating the Gemfile.

**Step 4: Run tests**

```
bin/rails test test/lib/ruby_llm/chat_step_test.rb
```

**Step 5: Run full suite**

```
bin/ci
```

**Step 6: Commit**

```bash
git add Gemfile Gemfile.lock test/lib/ruby_llm/chat_step_test.rb
git commit -m "feat: add Chat#step to RubyLLM fork — step is primitive, complete delegates to it"
```

---

### Task 2: Update ConversationRunner to use `chat.step`

Replace `run_llm` + `BroadcastMessagesJob` with `run_step` (inline broadcast) and `finish_or_reenqueue`.

**Files:**
- Modify: `lib/daan/conversation_runner.rb`
- Delete: `app/jobs/broadcast_messages_job.rb`
- Modify: `test/lib/daan/conversation_runner_test.rb` (update stubs and assertions)

**Step 1: Write failing tests**

Add tests covering the two branches of `finish_or_reenqueue`:

```ruby
# In test/lib/daan/conversation_runner_test.rb

test "re-enqueues LlmJob when response has tool calls" do
  chat = chats(:in_progress_chat)   # fixture with in_progress status
  agent = Daan::AgentRegistry.find(chat.agent_name)

  tool_response = OpenStruct.new("tool_call?" => true, role: "assistant", tool_calls: {})
  Daan::ConversationRunner.stub(:run_step, tool_response) do
    assert_enqueued_with(job: LlmJob, args: [chat]) do
      Daan::ConversationRunner.finish_or_reenqueue(chat, agent, tool_response)
    end
  end
end

test "calls finish_conversation when response has no tool calls" do
  chat = chats(:in_progress_chat)
  agent = Daan::AgentRegistry.find(chat.agent_name)

  final_response = OpenStruct.new("tool_call?" => false, role: "assistant", tool_calls: {})
  finish_called = false
  Daan::ConversationRunner.stub(:finish_conversation, ->(_c, _a) { finish_called = true }) do
    Daan::ConversationRunner.stub(:broadcast_typing, nil) do
      Daan::ConversationRunner.finish_or_reenqueue(chat, agent, final_response)
    end
  end
  assert finish_called
end

test "BroadcastMessagesJob is gone" do
  refute defined?(BroadcastMessagesJob), "BroadcastMessagesJob should be deleted"
end
```

**Step 2: Run to confirm failures**

```
bin/rails test test/lib/daan/conversation_runner_test.rb
```

**Step 3: Update ConversationRunner**

Key changes to `call`:
- Remove `last_message_id` capture
- Replace `run_llm` call with `run_step`
- Remove `BroadcastMessagesJob.perform_later`
- Replace `broadcast_typing(chat, false)` + `finish_conversation` with `finish_or_reenqueue`

```ruby
def self.call(chat)
  tag = "[ConversationRunner] chat_id=#{chat.id} agent=#{chat.agent_name}"
  agent = chat.agent

  start_conversation(chat)
  prepare_workspace(agent)
  enqueue_compaction_if_needed(chat)
  configure_llm(chat, agent)

  Rails.logger.info("#{tag} calling LLM model=#{chat.model_id}")
  llm_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  response = run_step(chat)
  llm_elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - llm_started_at).round(1)
  Rails.logger.info("#{tag} LLM step complete elapsed=#{llm_elapsed}s tool_call=#{response.tool_call?}")

  finish_or_reenqueue(chat, agent, response)
end
```

Replace `run_llm` with `run_step` (inline broadcast, same error handling):

```ruby
def self.run_step(chat)
  response = chat.step
  broadcast_step(chat, response)
  response
rescue => e
  tag = "[ConversationRunner] chat_id=#{chat.id}"
  Rails.logger.error("#{tag} LLM failed error=#{e.class}: #{e.message}")
  Rails.logger.error("#{tag} #{e.backtrace&.first(10)&.join("\n")}")
  chat.fail!
  chat.broadcast_agent_status
  broadcast_typing(chat, false)
  begin
    notify_parent_of_termination(chat, :failed)
  rescue => notify_error
    Rails.logger.error("#{tag} parent notification failed: #{notify_error.class}: #{notify_error.message}")
  end
  raise
end
private_class_method :run_step
```

Add `broadcast_step` (replaces the per-step portion of `broadcast_new_messages`):

```ruby
def self.broadcast_step(chat, response)
  # Only broadcast assistant messages — tool results are rendered inline with them
  return unless response.role.to_s == "assistant"

  # Collect tool results for this response's tool calls
  tool_call_ids = response.tool_calls&.keys&.map(&:to_s) || []
  results = if tool_call_ids.any?
    Message.where(role: "tool", tool_call_id: tool_call_ids)
           .index_by(&:tool_call_id)
           .transform_values(&:content)
  else
    {}
  end

  # response may be a RubyLLM::Message — fetch the persisted AR record for rendering
  ar_message = response.is_a?(Message) ? response : Message.find_by(
    chat_id: chat.id, role: "assistant"
  )

  return unless ar_message

  Turbo::StreamsChannel.broadcast_append_to(
    "chat_#{chat.id}",
    target: "messages",
    renderable: ChatMessageComponent.new(message: ar_message, results: results)
  )
end
private_class_method :broadcast_step
```

Add `finish_or_reenqueue`:

```ruby
def self.finish_or_reenqueue(chat, agent, response)
  if response.tool_call?
    # Agent is still working — re-enqueue, keep typing indicator on
    LlmJob.perform_later(chat)
  else
    broadcast_typing(chat, false)
    finish_conversation(chat, agent)
  end
end
private_class_method :finish_or_reenqueue
```

Remove `run_llm` and the old `broadcast_new_messages` public method entirely.

**Step 4: Delete BroadcastMessagesJob**

```bash
rm app/jobs/broadcast_messages_job.rb
```

**Step 5: Run tests**

```
bin/rails test test/lib/daan/conversation_runner_test.rb
```

**Step 6: Run full suite**

```
bin/ci
```

**Step 7: Commit**

```bash
git add lib/daan/conversation_runner.rb \
        test/lib/daan/conversation_runner_test.rb
git rm app/jobs/broadcast_messages_job.rb
git commit -m "feat: ConversationRunner uses chat.step — inline broadcast, re-enqueue on tool calls, remove BroadcastMessagesJob"
```

---

## Demo Script

1. Start the app: `bin/dev`
2. Open the Rails console in another terminal and watch the job queue: `bin/rails console`
3. Message any agent with a task that requires tool use (e.g. "List the agents on the team")
4. Observe in the logs: multiple `[LlmJob]` entries for the same `chat_id`, each completing quickly
5. Verify the agent's response appears in the UI as before
6. Verify `BroadcastMessagesJob` no longer appears in the logs

**Regression check:** Agents that respond without tools (single LLM call, no re-enqueue) should complete in one job, same as before.
