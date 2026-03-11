---
shaping: true
---

# V6: Self-modification

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Agents can run git and GitHub CLI commands from their workspace via a general-purpose `Bash` tool. The allowed binaries are declared per-agent in the agent definition — no new Ruby classes needed to add `gh`, `npm`, or any other tool. Demo: Developer clones this repo, creates a feature branch, writes a new agent definition file, commits, pushes, and opens a PR.

**Architecture:**
- `Daan::Core::Bash` — accepts `commands` (array of command arrays, e.g. `[["git","add","-A"],["git","commit","-m","msg"]]`) and optional `path` (workspace-relative working directory). Multiple commands can be batched in one call; each command's output is labelled separately in the result. Checks each command's first element against `@allowed_commands`. Runs each via `Open3.capture3` (no shell, no injection risk).
- `allowed_commands` — new YAML field in agent definition (e.g. `allowed_commands: [git, gh]`). Parsed by `AgentLoader`, stored on `Daan::Agent`, passed to every tool at instantiation via `Agent#tools`. Tools that don't use it absorb it silently via `**`.
- Developer agent gains `allowed_commands: [git, gh]` and `Daan::Core::Bash` in its tool list.
- `gh repo clone` handles cloning and sets up `gh` as a git credential helper — subsequent `git push` calls work without additional token configuration. `GITHUB_TOKEN` is read by `gh` automatically.

**Not in V6:** Per-subcommand restrictions within an allowed binary (allowing `git` means trusting all git operations — consistent with D26). Concurrent command execution. Streaming output. Shell string syntax (`&&`, `|`, `;`) — use the `commands` array for sequencing instead. Argument-level path validation within commands (Bash sandboxes the working directory, not the arguments passed to the binary — conscious V1 tradeoff per D26).

**Tech Stack:** Rails 8.1, stdlib `Open3`, Minitest

---

## Implementation Plan

### Task 1: `allowed_commands` in Agent + AgentLoader + existing tool signatures

`Agent#tools` passes `allowed_commands:` to every tool at instantiation. Existing tools absorb it silently with `**`. This is the one-time plumbing change that makes all future tools like `Bash` work without further changes to `Agent`.

**Files:**
- Modify: `lib/daan/agent.rb`
- Modify: `lib/daan/agent_loader.rb`
- Modify: `lib/daan/core/read.rb`
- Modify: `lib/daan/core/write.rb`
- Modify: `lib/daan/core/delegate_task.rb`
- Modify: `lib/daan/core/report_back.rb`
- Modify (if V5 landed): `lib/daan/core/write_memory.rb`, `lib/daan/core/search_memory.rb`
- Create: `test/lib/daan/agent_allowed_commands_test.rb`

**Step 1: Write failing tests**

```ruby
# test/lib/daan/agent_allowed_commands_test.rb
require "test_helper"

class AgentAllowedCommandsTest < ActiveSupport::TestCase
  test "agent defaults allowed_commands to empty array" do
    agent = Daan::Agent.new(name: "test", display_name: "Test",
                             model_name: "claude-sonnet-4-20250514",
                             system_prompt: "You help.", max_turns: 5)
    assert_equal [], agent.allowed_commands
  end

  test "agent loader parses allowed_commands from frontmatter" do
    file = Tempfile.new(["agent", ".md"])
    file.write(<<~MD)
      ---
      name: tester
      display_name: Tester
      model: claude-sonnet-4-20250514
      max_turns: 5
      allowed_commands:
        - git
        - gh
      tools: []
      delegates_to: []
      ---
      You help.
    MD
    file.flush

    definition = Daan::AgentLoader.parse(file.path)
    assert_equal %w[git gh], definition[:allowed_commands]
  ensure
    file.close
    file.unlink
  end

  test "agent loader defaults allowed_commands to empty array when absent from frontmatter" do
    file = Tempfile.new(["agent", ".md"])
    file.write(<<~MD)
      ---
      name: tester
      display_name: Tester
      model: claude-sonnet-4-20250514
      max_turns: 5
      tools: []
      delegates_to: []
      ---
      You help.
    MD
    file.flush

    definition = Daan::AgentLoader.parse(file.path)
    assert_equal [], definition[:allowed_commands]
  ensure
    file.close
    file.unlink
  end

  test "agent tools receives allowed_commands at instantiation" do
    received = nil
    fake_tool = Class.new do
      define_method(:initialize) do |workspace: nil, chat: nil, allowed_commands: [], **|
        received = allowed_commands
      end
    end

    agent = Daan::Agent.new(
      name: "test", display_name: "Test",
      model_name: "claude-sonnet-4-20250514",
      system_prompt: "You help.", max_turns: 5,
      base_tools: [fake_tool],
      allowed_commands: %w[git gh]
    )
    agent.tools(chat: nil)
    assert_equal %w[git gh], received
  end
end
```

**Step 2: Run to confirm failures**

```
bin/rails test test/lib/daan/agent_allowed_commands_test.rb
```

**Step 3: Update Agent struct**

```ruby
# lib/daan/agent.rb
module Daan
  Agent = Struct.new(:name, :display_name, :model_name, :system_prompt, :max_turns,
                     :workspace, :base_tools, :delegates_to, :allowed_commands,
                     keyword_init: true) do
    def initialize(**)
      super
      self.base_tools       ||= []
      self.delegates_to     ||= []
      self.allowed_commands ||= []
    end

    def tools(chat: nil)
      base_tools.map { |t| t.new(workspace: workspace, chat: chat, allowed_commands: allowed_commands) }
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

**Step 4: Update AgentLoader**

```ruby
# lib/daan/agent_loader.rb — add allowed_commands to the parsed hash
{
  name:             fm.fetch("name"),
  display_name:     fm.fetch("display_name"),
  model_name:       fm.fetch("model"),
  max_turns:        fm.fetch("max_turns"),
  system_prompt:    parsed.content.strip,
  base_tools:       base_tools,
  workspace:        workspace,
  delegates_to:     fm.fetch("delegates_to", []),
  allowed_commands: fm.fetch("allowed_commands", [])
}
```

**Step 5: Add `**` to existing tool initializers**

Each existing tool absorbs unknown kwargs silently. `**` is intentional: "I don't use this, ignore it." Future injection concerns don't require revisiting these files again.

```ruby
# lib/daan/core/read.rb
def initialize(workspace: nil, chat: nil, **)

# lib/daan/core/write.rb
def initialize(workspace: nil, chat: nil, **)

# lib/daan/core/delegate_task.rb
def initialize(workspace: nil, chat: nil, **)

# lib/daan/core/report_back.rb
def initialize(workspace: nil, chat: nil, **)
```

If V5 has landed, do the same for `write_memory.rb` and `search_memory.rb`.

**Step 6: Run tests**

```
bin/rails test test/lib/daan/agent_allowed_commands_test.rb
```

Expected: all 4 tests pass.

**Step 7: Run full suite**

```
bin/rails test
```

Expected: all pass (no existing tool tests break).

**Step 8: Commit**

```bash
git add lib/daan/agent.rb \
        lib/daan/agent_loader.rb \
        lib/daan/core/read.rb \
        lib/daan/core/write.rb \
        lib/daan/core/delegate_task.rb \
        lib/daan/core/report_back.rb \
        test/lib/daan/agent_allowed_commands_test.rb
git commit -m "feat: allowed_commands — agent definition declares permitted binaries for Bash tool"
```

---

### Task 2: `Daan::Core::Bash` tool

Accepts an array of commands. Validates each binary against `@allowed_commands`. Runs each via `Open3.capture3` with no shell. Returns combined output labelled by command. Raises immediately on any failure — the LLM receives no partial output when a command fails mid-sequence.

**Files:**
- Create: `lib/daan/core/bash.rb`
- Create: `test/lib/daan/core/bash_test.rb`

**Step 1: Write failing tests**

```ruby
# test/lib/daan/core/bash_test.rb
require "test_helper"

class Daan::Core::BashTest < ActiveSupport::TestCase
  setup do
    @workspace_dir = Dir.mktmpdir
    @workspace = Daan::Workspace.new(@workspace_dir)
    @tool = Daan::Core::Bash.new(
      workspace: @workspace,
      allowed_commands: %w[echo git pwd]
    )
  end

  teardown do
    FileUtils.rm_rf(@workspace_dir)
  end

  test "runs a single allowed command and returns its output" do
    result = @tool.execute(commands: [["echo", "hello"]])
    assert_includes result, "hello"
  end

  test "runs multiple commands and returns all output" do
    result = @tool.execute(commands: [["echo", "first"], ["echo", "second"]])
    assert_includes result, "first"
    assert_includes result, "second"
  end

  test "returns empty string for empty commands array" do
    assert_equal "", @tool.execute(commands: [])
  end

  test "raises on disallowed binary" do
    error = assert_raises(RuntimeError) do
      @tool.execute(commands: [["rm", "-rf", "."]])
    end
    assert_match(/not allowed/, error.message)
  end

  test "raises on empty allowed_commands list" do
    tool = Daan::Core::Bash.new(workspace: @workspace, allowed_commands: [])
    error = assert_raises(RuntimeError) do
      tool.execute(commands: [["echo", "hi"]])
    end
    assert_match(/not allowed/, error.message)
  end

  test "raises when a command fails" do
    # workspace_dir is not a git repo — git status exits non-zero
    assert_raises(RuntimeError) do
      @tool.execute(commands: [["git", "status"]])
    end
  end

  test "raises on second command failure and returns no partial output" do
    error = assert_raises(RuntimeError) do
      @tool.execute(commands: [["echo", "step one"], ["git", "status"]])
    end
    assert_match(/git status/, error.message)
  end

  test "runs commands in workspace root by default" do
    result = @tool.execute(commands: [["pwd"]])
    assert_includes result, @workspace_dir
  end

  test "runs commands in specified subdirectory" do
    subdir = File.join(@workspace_dir, "subdir")
    FileUtils.mkdir_p(subdir)

    result = @tool.execute(commands: [["pwd"]], path: "subdir")
    assert_includes result, File.join(@workspace_dir, "subdir")
  end

  test "raises when path escapes workspace" do
    assert_raises(ArgumentError) do
      @tool.execute(commands: [["echo", "hi"]], path: "../escape")
    end
  end
end
```

**Step 2: Run to confirm failures**

```
bin/rails test test/lib/daan/core/bash_test.rb
```

**Step 3: Implement Bash**

```ruby
# lib/daan/core/bash.rb
require "open3"

module Daan
  module Core
    class Bash < RubyLLM::Tool
      description "Run one or more commands in the workspace. Each command is an array of " \
                  "strings: the binary plus its arguments. Commands run sequentially in the " \
                  "specified directory. Only binaries listed in allowed_commands may be used. " \
                  "If any command fails, an error is raised and no output is returned."
      param :commands, desc: "Commands to run, each as [binary, arg1, arg2, ...]. " \
                             "Example: [[\"git\", \"add\", \"-A\"], [\"git\", \"commit\", \"-m\", \"msg\"]]"
      param :path,     desc: "Working directory relative to workspace (optional, defaults to workspace root)"

      def initialize(workspace: nil, chat: nil, allowed_commands: [], **)
        @workspace        = workspace
        @allowed_commands = allowed_commands
      end

      def execute(commands:, path: nil)
        return "" if commands.empty?

        dir = path ? @workspace.resolve(path) : @workspace.root

        outputs = commands.map do |cmd|
          binary = cmd.first
          unless @allowed_commands.include?(binary)
            raise "Command '#{binary}' is not allowed. Permitted: #{@allowed_commands.join(', ')}"
          end

          stdout, stderr, status = Open3.capture3(*cmd, chdir: dir.to_s)
          unless status.success?
            output = [ stdout, stderr ].reject(&:empty?).join("\n")
            raise "#{cmd.join(' ')} failed (exit #{status.exitstatus}): #{output}"
          end

          "$ #{cmd.join(' ')}\n#{stdout}"
        end

        outputs.join("\n")
      end
    end
  end
end
```

**Step 4: Run tests**

```
bin/rails test test/lib/daan/core/bash_test.rb
```

Expected: all 10 tests pass.

**Step 5: Run full suite**

```
bin/rails test
```

**Step 6: Commit**

```bash
git add lib/daan/core/bash.rb test/lib/daan/core/bash_test.rb
git commit -m "feat: Bash tool — run allowed commands in workspace; binary allowlist from agent definition"
```

---

### Task 3: Wire Bash into Developer agent definition

Add `Daan::Core::Bash` to the Developer's tool list, set `allowed_commands: [git, gh]`, raise `max_turns`, and update the system prompt with self-modification instructions. Assumes V5 has landed (WriteMemory/SearchMemory already in the definition).

**Files:**
- Modify: `lib/daan/core/agents/developer.md`

**Step 1: Update developer.md**

```markdown
---
name: developer
display_name: Developer
model: claude-sonnet-4-20250514
max_turns: 15
workspace: tmp/workspaces/developer
delegates_to: []
allowed_commands:
  - git
  - gh
tools:
  - Daan::Core::Read
  - Daan::Core::Write
  - Daan::Core::Bash
  - Daan::Core::ReportBack
  - Daan::Core::WriteMemory
  - Daan::Core::SearchMemory
---
You are the Developer on the Daan agent team. You write and modify files in your workspace to accomplish technical tasks.

When you receive a task:
1. Use your Read and Write tools to complete the work. Use relative paths — they resolve within your workspace.
2. When your work is complete, use ReportBack to send your findings to your delegator. Be concise — share what you did and what you found.
3. After calling ReportBack, your work in this thread is done — do not send any further messages.

Use WriteMemory to save useful facts about codebases, patterns, or approaches you discover. Use SearchMemory to recall context about a project you've worked on before.

When asked to make a code change to a repository and open a pull request:
1. Bash: `["gh", "repo", "clone", "<owner/repo>", "<destination>"]` — clones the repo and sets up gh as a credential helper so subsequent git pushes work without token configuration.
2. Bash: `["git", "checkout", "-b", "<branch-name>"]` with path set to the destination — creates your working branch.
3. Use Write (and Read if needed) to make the file changes. Use path relative to the destination directory inside your workspace.
4. Bash: `[["git", "add", "-A"], ["git", "commit", "-m", "<message>"]]` with path set to the destination — stage and commit in one call.
5. Bash: `["git", "push", "origin", "<branch-name>"]` with path set to the destination — pushes the branch. Requires GITHUB_TOKEN env var; if it is not set, report back immediately.
6. Bash: `["gh", "pr", "create", "--title", "<title>", "--body", "<body>", "--base", "main", "--head", "<branch-name>"]` with path set to the destination — opens the PR and returns its URL.
7. ReportBack with the PR URL so your delegator can share it with the human.
```

Note: `max_turns` is raised from 10 to 15 to accommodate the clone→branch→write→commit→push→PR workflow.

**Step 2: Verify agent loader picks up Bash and allowed_commands**

```ruby
# rails console
Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
agent = Daan::AgentRegistry.find("developer")
agent.allowed_commands  # => ["git", "gh"]
tools = agent.tools(chat: Chat.new)
bash  = tools.find { |t| t.is_a?(Daan::Core::Bash) }
bash  # should not be nil
```

**Step 3: Run full test suite**

```
bin/rails test
```

Expected: all pass.

**Step 4: Commit**

```bash
git add lib/daan/core/agents/developer.md
git commit -m "feat: wire Bash tool into Developer — git + gh allowed for self-modification"
```

---

## Demo Script

**Prerequisites:**
- `GITHUB_TOKEN` set to a PAT with `repo` scope
- `gh` CLI installed and on PATH (`brew install gh` or equivalent)
- The target repo exists on GitHub and the token has write access

**Steps:**

1. Start the app: `bin/dev`

2. Message the CoS:
   > "Have the developer add a new agent definition for a QA Engineer to the ramontayag/daan-rails repo and open a PR."

3. Watch the delegation chain: CoS → EM → Developer.

4. Watch the Developer's thread — tool call blocks appear for each step:
   - `gh repo clone ramontayag/daan-rails daan-rails`
   - `git checkout -b feature/add-qa-agent` (path: daan-rails)
   - `Write` — creates `lib/daan/core/agents/qa_engineer.md`
   - `git add -A` + `git commit -m "feat: add QA Engineer agent"` batched in one Bash call (path: daan-rails)
   - `git push origin feature/add-qa-agent` (path: daan-rails)
   - `gh pr create --title "Add QA Engineer agent" ...` (path: daan-rails)
   - `ReportBack` with the PR URL

5. Results flow back: Developer → EM → CoS → human.

6. Human sees the PR URL. Review and merge on GitHub.

7. Optional: switch to Developer perspective to see the full tool call trace from the Developer's point of view (D16/A8).
