---
shaping: true
---

# V9: Developer Self-Modifies in Dev

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** The Developer can push a feature branch to `DAAN_SELF_REPO` and immediately see the changes in the running app via `MergeBranchToSelf`. In production the tool is absent — the Developer opens a PR to `main` instead (already works via V6). This slice makes dev self-modification a first-class workflow.

**Architecture:**
- `Daan::Core::MergeBranchToSelf` — new tool, param: `branch`. Runs `git fetch && git checkout develop && git merge origin/<branch>` in `Rails.root`, then calls `AgentLoader.sync!`. Only available in dev via `config/agents/developer.md` override.
- `config/agents/developer.md` — new file in `config/agents/`, adds `MergeBranchToSelf` to the Developer's tool list. This file only exists in dev environments (not committed for prod deployments, or managed via env-specific config).
- `DAAN_SELF_REPO` env var — already used by the Developer via Bash to clone the repo. No new usage needed; the tool operates on `Rails.root` which is always the self repo in dev.
- `AgentLoader.sync!` — existing method; called after merge so new/changed agent definitions take effect without restart.
- Developer system prompt — updated to describe the dev self-modification workflow step that calls `MergeBranchToSelf` after pushing.

**Git flow assumption:** A `develop` branch exists on `DAAN_SELF_REPO`. Create it before running the demo if it doesn't exist.

**Not in V9:** ARM git access (V10). Running `db:migrate` after merge (add later if needed — Rails dev mode picks up most changes without it).

**Tech Stack:** Rails 8.1, stdlib `Open3`, Minitest

---

## Implementation Plan

### Task 1: `Daan::Core::MergeBranchToSelf` tool

**Files:**
- Create: `lib/daan/core/merge_branch_to_self.rb`
- Create: `test/lib/daan/core/merge_branch_to_self_test.rb`

**Step 1: Write failing tests**

```ruby
# test/lib/daan/core/merge_branch_to_self_test.rb
require "test_helper"

class Daan::Core::MergeBranchToSelfTest < ActiveSupport::TestCase
  test "absorbs unknown kwargs silently" do
    assert_nothing_raised do
      Daan::Core::MergeBranchToSelf.new(workspace: nil, chat: nil, allowed_commands: [])
    end
  end

  test "calls git fetch, checkout develop, merge, then AgentLoader.sync!" do
    tool = Daan::Core::MergeBranchToSelf.new
    commands_run = []

    Open3.stub(:capture3, ->(cmd, **opts) {
      commands_run << cmd
      ["", "", stub(success?: true)]
    }) do
      Daan::AgentLoader.stub(:sync!, nil) do
        tool.execute(branch: "feature/test-branch")
      end
    end

    assert_includes commands_run, "git fetch origin"
    assert_includes commands_run, "git checkout develop"
    assert_includes commands_run, "git merge origin/feature/test-branch"
  end

  test "raises if git command fails" do
    tool = Daan::Core::MergeBranchToSelf.new

    Open3.stub(:capture3, ->(*) {
      ["", "fatal: branch not found", stub(success?: false, exitstatus: 128)]
    }) do
      assert_raises(RuntimeError) do
        tool.execute(branch: "feature/nonexistent")
      end
    end
  end
end
```

**Step 2: Run to confirm failures**

```
bin/rails test test/lib/daan/core/merge_branch_to_self_test.rb
```

**Step 3: Implement**

```ruby
# lib/daan/core/merge_branch_to_self.rb
require "open3"

module Daan
  module Core
    class MergeBranchToSelf < RubyLLM::Tool
      description "Merge a feature branch into the develop branch of the running app and " \
                  "hot-reload agent definitions. Call this after pushing a self-modification " \
                  "branch to see changes immediately. Only use in development."
      param :branch, desc: "The feature branch name to merge into develop (e.g. 'feature/add-qa-agent')"

      def initialize(**)
      end

      def execute(branch:)
        app_root = Rails.root.to_s
        run!("git fetch origin", app_root)
        run!("git checkout develop", app_root)
        run!("git merge origin/#{branch}", app_root)
        Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
        "Merged origin/#{branch} into develop and reloaded agent definitions."
      end

      private

      def run!(cmd, dir)
        stdout, stderr, status = Open3.capture3(cmd, chdir: dir)
        return if status.success?
        output = [ stdout, stderr ].reject(&:empty?).join("\n")
        raise "#{cmd} failed (exit #{status.exitstatus}): #{output}"
      end
    end
  end
end
```

**Step 4: Run tests**

```
bin/rails test test/lib/daan/core/merge_branch_to_self_test.rb
```

**Step 5: Run full suite**

```
bin/rails test && bin/rails test:system
```

**Step 6: Commit**

```bash
git add lib/daan/core/merge_branch_to_self.rb test/lib/daan/core/merge_branch_to_self_test.rb
git commit -m "feat: MergeBranchToSelf tool — merge feature branch into develop and hot-reload agents"
```

---

### Task 2: Developer dev override + system prompt update

**Files:**
- Create: `config/agents/developer.md`

**Step 1: Create config/agents/ directory if absent and add developer.md override**

The override adds `MergeBranchToSelf` to the tool list and appends a dev self-modification workflow step to the system prompt.

```markdown
---
name: developer
display_name: Developer
model: claude-sonnet-4-20250514
max_turns: 20
workspace: tmp/workspaces/developer
delegates_to: []
allowed_commands:
  - git
  - gh
  - ls
tools:
  - Daan::Core::Read
  - Daan::Core::Write
  - Daan::Core::Bash
  - Daan::Core::ReportBack
  - Daan::Core::MergeBranchToSelf
  - SwarmMemory::Tools::MemoryWrite
  - SwarmMemory::Tools::MemoryRead
  - SwarmMemory::Tools::MemoryEdit
  - SwarmMemory::Tools::MemoryDelete
  - SwarmMemory::Tools::MemoryGlob
  - SwarmMemory::Tools::MemoryGrep
---
You are the Developer on the Daan agent team. You write and modify files in your workspace to accomplish technical tasks.

{{include: partials/autonomy.md}}

When you receive a task:
1. Search memory for relevant context, patterns, or past decisions.
2. Use your Read and Write tools to complete the work. Use relative paths — they resolve within your workspace.
3. When your work is complete, use ReportBack to send your findings to your delegator. Note any assumptions you made or choices between alternatives — be concise.
4. After calling ReportBack, your work in this thread is done — do not send any further messages.

{{include: partials/memory_tools.md}} When writing memories, include a confidence level (high/medium/low), relevant tags, and a clear title.

When asked to make a code change to a repository and open a pull request:
1. Bash: `[["gh", "repo", "clone", "<owner/repo>", "<destination>"]]` — clones the repo and sets up gh as a credential helper so subsequent git pushes work without token configuration.
2. Bash: `[["git", "checkout", "-b", "<branch-name>"]]` with path set to the destination — creates your working branch.
3. Use Write (and Read if needed) to make the file changes. Use path relative to the destination directory inside your workspace.
4. Bash: `[["git", "add", "-A"], ["git", "commit", "-m", "<message>"]]` with path set to the destination — stage and commit in one call.
5. Bash: `[["git", "push", "origin", "<branch-name>"]]` with path set to the destination — pushes the branch.
6. **In development (you have MergeBranchToSelf):** Call MergeBranchToSelf with the branch name — this merges the branch into develop in the running app and reloads agent definitions immediately. Skip opening a PR.
7. **In production (no MergeBranchToSelf):** Bash: `[["gh", "pr", "create", "--title", "<title>", "--body", "<body>", "--base", "main", "--head", "<branch-name>"]]` — opens the PR and returns its URL.
8. ReportBack with the outcome (merge confirmation in dev, PR URL in prod).
```

**Step 2: Ensure `config/agents/` is picked up by AgentLoader**

Verify `Daan::AgentLoader` loads from `config/agents/` with same-name-wins precedence (per D13/A2 in shaping.md). If not yet implemented, add it now.

```ruby
# In AgentLoader.sync! or wherever definitions are loaded:
# 1. Load lib/daan/core/agents/*.md
# 2. Load config/agents/*.md — same-name file takes precedence
```

**Step 3: Run full suite**

```
bin/rails test && bin/rails test:system
```

**Step 4: Commit**

```bash
git add config/agents/developer.md
git commit -m "feat: dev override for Developer — adds MergeBranchToSelf for immediate self-mod in development"
```

---

## Pre-Demo Setup

Ensure a `develop` branch exists on `DAAN_SELF_REPO`:

```bash
git checkout -b develop
git push origin develop
```

## Demo Script

1. Start the app: `bin/dev`
2. Message the CoS: *"Have the developer add a comment to the chief_of_staff.md system prompt saying 'Hello from self-modification' and apply it."*
3. Watch the Developer thread:
   - `gh repo clone ramontayag/daan-rails daan-rails`
   - `git checkout -b feature/hello-self-mod`
   - `Write` — edits `lib/daan/core/agents/chief_of_staff.md`
   - `git add -A` + `git commit`
   - `git push origin feature/hello-self-mod`
   - `MergeBranchToSelf('feature/hello-self-mod')`
   - `ReportBack`
4. Refresh the app — the CoS agent definition now includes the comment, no restart needed.
