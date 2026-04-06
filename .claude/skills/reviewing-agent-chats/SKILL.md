---
name: reviewing-agent-chats
description: Review Daan agent chat transcripts to identify problems in agent behavior, prompts, tools, and workflow. Use when studying completed chats, diagnosing agent failures, or looking for systematic improvements to the agent system.
---

# Reviewing Agent Chats

Study completed agent chats to find problems and improve the system.

## Quick Start

Load a chat and its messages:

```ruby
bin/rails runner "
chat = Chat.find(CHAT_ID)
chat.messages.order(:created_at).each { |m|
  puts \"MSG #{m.id} [#{m.role}] visible=#{m.visible} tool_calls=#{m.tool_calls.present?}\"
  puts m.content.to_s[0..500]
  puts '---'
}
"
```

For sub-chats (delegated work), also load them:

```ruby
bin/rails runner "
Chat.find(CHAT_ID).sub_chats.each { |sc|
  puts \"Sub-chat #{sc.id} agent=#{sc.agent_name} status=#{sc.task_status}\"
}
"
```

## What to Look For

### Wasted Steps

Agents have limited steps. Every wasted step is costly.

- **Workspace escape errors**: Agent tried to read/write outside its workspace. Check if the workspace instructions in `agent_loader.rb` are clear enough, or if the agent needs a command added to `allowed_commands`.
- **Denied commands**: Search for `"not allowed"` or `"Permitted:"` in tool messages. If a command is legitimately needed, add it to the agent's `allowed_commands` in its `.md` file.
- **Blind exploration**: Agent spent many steps searching for a file it could have found in 1-2 steps. May indicate the agent needs better context in its delegation message, or the prompt should guide it to ask first.
- **Repeated failures**: Agent retried the same failing approach. Check if the error message was unclear or if the prompt lacks guidance for that scenario.

### Misunderstood Tasks

- **Wrong task executed**: Compare what the human asked (first user message) with what the agent actually did. If they diverge, trace where the misunderstanding happened -- was it the human's message, the EM's delegation, or the agent's interpretation?
- **Scope creep**: Agent built features beyond what was requested. Check if the delegation message was too broad, or if a corrective follow-up was treated as additive rather than replacing.
- **Assumptions instead of questions**: Agent assumed what the human meant instead of asking. Especially watch for this in top-level chats (no parent_chat).

### Delegation Problems

- **Vague delegation**: The DelegateTask message lacked enough context for the sub-agent to succeed. Compare the human's request with what the EM delegated.
- **Wrong agent chosen**: Task was delegated to an agent without the right tools or expertise.
- **Lost corrections**: Human corrected the EM, but the EM's follow-up to the sub-agent didn't clearly replace the original instructions.

### Invisible Message Problems

- **System messages**: Messages with `visible: false` are injected by the system (step limit warnings, report-backs, parent notifications). Check if they're clear enough for the receiving agent to act on.
- **ReportBack content**: Is the report specific about what was requested vs. what was done? Does it give the parent agent enough info to verify?
- **Step limit warnings**: Did the agent get the warning and act on it (call report_back), or did it ignore it?

### Step Limit Issues

- **Hit limit too early**: Agent ran out of steps before completing work. Check if `max_steps` is too low for the agent's role, or if the agent wasted steps.
- **Hit limit without reporting**: Agent hit the limit without calling `report_back`. The ForceReportBack kicks in, but the summary is often lower quality. Check if the "reporting back" instruction in `autonomy.md` is being followed.

### Tool and Prompt Issues

- **Missing tools**: Agent needed a capability it didn't have. Consider adding the tool to its config.
- **Prompt gaps**: Agent behaved in a way that's technically correct but undesirable. Note the gap for a prompt improvement.
- **Prompt ignored**: Agent had clear instructions but didn't follow them. May need stronger wording, or the instruction may be buried too deep in the prompt.

## Output

After reviewing, report:

1. **What went wrong** -- specific problems with message IDs
2. **Root cause** -- prompt gap, tool issue, delegation problem, or step limit
3. **Recommended fix** -- concrete change to a prompt, partial, tool, or agent config
4. **Priority** -- how often this is likely to recur

Focus on systemic issues (prompt gaps, missing tools, unclear instructions) over one-off mistakes.
