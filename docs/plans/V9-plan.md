---
shaping: true
---

# V9: Developer Self-Modifies in Dev

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** The Developer can push a feature branch to `DAAN_SELF_REPO` and immediately see the changes in the running app via `MergeBranchToSelf`. In production the tool is absent — the Developer opens a PR to `main` instead (already works via V6). This slice makes dev self-modification a first-class workflow.

**Architecture:**
- `config/agents/` override directory — loaded after `lib/daan/core/agents/` in development only. Same-name file wins. Committed to the repo; the initializer only loads it in development, so prod is unaffected.
- `Daan::Core::MergeBranchToSelf` — new tool, param: `branch`. Runs `git fetch origin`, `git checkout develop`, `git merge origin/<branch>` in `Rails.root` (array form, no shell), then re-syncs both agent directories. Only available in dev via `config/agents/developer.md` override.
- `config/agents/developer.md` — dev override adding `MergeBranchToSelf` to the Developer's tool list.
- `DAAN_SELF_REPO` env var — injected into agent workspace instructions by `AgentLoader` (already implemented).

**Git flow assumption:** A `develop` branch exists on `DAAN_SELF_REPO`. Create it before running the demo if it doesn't exist.

**Not in V9:** ARM git access (V10). Running `db:migrate` after merge.

**Tech Stack:** Rails 8.1, stdlib `Open3`, Minitest

---

## Implementation Plan

### Task 1: Load `config/agents/` overrides in development

The initializer currently only loads `lib/daan/core/agents/`. Override support must land before `MergeBranchToSelf` exists, because `MergeBranchToSelf#execute` must re-sync both directories so the Developer doesn't lose its own tool after a sync.

**Files:**
- Create: `config/agents/.gitkeep`
- Modify: `config/initializers/daan.rb`
- Create: `test/lib/daan/agent_loader_override_test.rb`

**Step 1: Write failing test**

```ruby
# test/lib/daan/agent_loader_override_test.rb
require "test_helper"

class AgentLoaderOverrideTest < ActiveSupport::TestCase
  test "config/agents/ override takes precedence over lib/daan/core/agents/" do
    base_dir = Dir.mktmpdir
    override_dir = Dir.mktmpdir

    File.write(File.join(base_dir, "tester.md"), <<~MD)
      ---
      name: tester
      display_name: Tester Base
      model: claude-sonnet-4-20250514
      max_turns: 5
      ---
      Base prompt.
    MD

    File.write(File.join(override_dir, "tester.md"), <<~MD)
      ---
      name: tester
      display_name: Tester Override
      model: claude-sonnet-4-20250514
      max_turns: 5
      ---
      Override prompt.
    MD

    Daan::AgentLoader.sync!(base_dir)
    Daan::AgentLoader.sync!(override_dir)

    agent = Daan::AgentRegistry.find("tester")
    assert_equal "Tester Override", agent.display_name
  ensure
    FileUtils.rm_rf(base_dir)
    FileUtils.rm_rf(override_dir)
  end
end
```

**Step 2: Run to confirm the test passes**

`sync!` called twice already gives override-wins behaviour because `AgentRegistry.register` overwrites by name. This test should pass immediately — confirming the contract before we rely on it.

```
bin/rails test test/lib/daan/agent_loader_override_test.rb
```

**Step 3: Update initializer to load overrides in development**

```ruby
# config/initializers/daan.rb
Rails.application.config.to_prepare do
  next if Rails.env.test? # Tests load the registry explicitly in setup
  Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
  if Rails.env.development?
    override_dir = Rails.root.join("config/agents")
    Daan::AgentLoader.sync!(override_dir) if override_dir.exist?
  end
end
```

**Step 4: Create `config/agents/` directory**

```bash
mkdir -p config/agents
touch config/agents/.gitkeep
```

**Step 5: Run full suite**

```
bin/rails test && bin/rails test:system
```

**Step 6: Commit**

```bash
git add config/initializers/daan.rb config/agents/.gitkeep \
        test/lib/daan/agent_loader_override_test.rb
git commit -m "feat: load config/agents/ overrides in development — same-name file wins"
```

---

### Task 2: `Daan::Core::MergeBranchToSelf` tool

**Files:**
- Create: `lib/daan/core/merge_branch_to_self.rb`
- Create: `test/lib/daan/core/merge_branch_to_self_test.rb`

**Step 1: Write failing tests**

```ruby
# test/lib/daan/core/merge_branch_to_self_test.rb
require "test_helper"

class Daan::Core::MergeBranchToSelfTest < ActiveSupport::TestCase
  def fake_status(success:, exitstatus: 0)
    s = Object.new
    s.define_singleton_method(:success?) { success }
    s.define_singleton_method(:exitstatus) { exitstatus }
    s
  end

  test "runs git fetch, checkout develop, merge in sequence" do
    commands_run = []
    tool = Daan::Core::MergeBranchToSelf.new

    Open3.stub(:capture3, ->(*cmd, **_opts) {
      commands_run << cmd
      ["", "", fake_status(success: true)]
    }) do
      Daan::AgentLoader.stub(:sync!, ->(*) {}) do
        tool.execute(branch: "feature/test-branch")
      end
    end

    assert_equal [%w[git fetch origin],
                  %w[git checkout develop],
                  %w[git merge origin/feature/test-branch]], commands_run
  end

  test "calls AgentLoader.sync! for both agent directories" do
    synced_dirs = []
    tool = Daan::Core::MergeBranchToSelf.new

    Open3.stub(:capture3, ->(*_cmd, **_opts) {
      ["", "", fake_status(success: true)]
    }) do
      Daan::AgentLoader.stub(:sync!, ->(dir) { synced_dirs << dir.to_s }) do
        tool.execute(branch: "feature/test-branch")
      end
    end

    assert_includes synced_dirs, Rails.root.join("lib/daan/core/agents").to_s
    assert_includes synced_dirs, Rails.root.join("config/agents").to_s
  end

  test "raises if a git command fails" do
    tool = Daan::Core::MergeBranchToSelf.new

    Open3.stub(:capture3, ->(*_cmd, **_opts) {
      ["", "fatal: branch not found", fake_status(success: false, exitstatus: 128)]
    }) do
      assert_raises(RuntimeError) { tool.execute(branch: "feature/nonexistent") }
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

      def initialize(workspace: nil, chat: nil, storage: nil, agent_name: nil, allowed_commands: nil)
      end

      def execute(branch:)
        app_root = Rails.root.to_s
        run!(%w[git fetch origin], app_root)
        run!(%w[git checkout develop], app_root)
        run!(["git", "merge", "origin/#{branch}"], app_root)
        Daan::AgentLoader.sync!(Rails.root.join("lib/daan/core/agents"))
        override_dir = Rails.root.join("config/agents")
        Daan::AgentLoader.sync!(override_dir) if override_dir.exist?
        "Merged origin/#{branch} into develop and reloaded agent definitions."
      end

      private

      def run!(cmd, dir)
        stdout, stderr, status = Open3.capture3(*cmd, chdir: dir)
        return if status.success?
        output = [ stdout, stderr ].reject(&:empty?).join("\n")
        raise "#{cmd.join(' ')} failed (exit #{status.exitstatus}): #{output}"
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
git add lib/daan/core/merge_branch_to_self.rb \
        test/lib/daan/core/merge_branch_to_self_test.rb
git commit -m "feat: MergeBranchToSelf tool — merge feature branch into develop and hot-reload agents"
```

---

### Task 3: Developer dev override + system prompt update

**Files:**
- Create: `config/agents/developer.md`

**Step 1: Create the dev override**

Copy the full current `lib/daan/core/agents/developer.md` content, add `Daan::Core::MergeBranchToSelf` to the tools list, and extend the PR workflow steps to include the dev path. Keep `max_turns: 15`.

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
5. Bash: `[["git", "push", "origin", "<branch-name>"]]` with path set to the destination — pushes the branch. Authentication is handled automatically by `gh repo clone`. Do not run `gh auth login` — it requires interactive input and will time out.
6. **In development (you have MergeBranchToSelf):** Call MergeBranchToSelf with the branch name — this merges the branch into develop in the running app and reloads agent definitions immediately. Skip opening a PR.
7. **In production (no MergeBranchToSelf):** Bash: `[["gh", "pr", "create", "--title", "<title>", "--body", "<body>", "--base", "main", "--head", "<branch-name>"]]` — opens the PR and returns its URL.
8. ReportBack with the outcome (merge confirmation in dev, PR URL in prod).
```

**Step 2: Run full suite**

```
bin/rails test && bin/rails test:system
```

**Step 3: Commit**

```bash
git add config/agents/developer.md
git commit -m "feat: dev override for Developer — MergeBranchToSelf for immediate self-mod in development"
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
