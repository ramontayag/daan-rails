---
shaping: true
---

# V10: ARM Self-Modifies Agent Definitions

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** The Agent Resource Manager can create and edit agent definitions through git — cloning `DAAN_SELF_REPO` into its workspace, using `CreateAgent`/`EditAgent` to write into the clone, committing, pushing, and (in dev) merging immediately via `MergeBranchToSelf`. In production it opens a PR to `main`.

**Architecture:**
- `CreateAgent` / `EditAgent` — updated to accept a configurable `agents_dir` at tool instantiation (already partially supported; ensure it resolves relative to the workspace, not `Rails.root`). When ARM uses these tools inside a cloned repo in its workspace, the path resolves correctly.
- `config/agents/agent_resource_manager.md` — dev override that adds `allowed_commands: [git, gh]`, `Daan::Core::Bash`, and `Daan::Core::MergeBranchToSelf` to the ARM's tool list.
- ARM system prompt — updated to describe the git-based agent creation workflow.
- ARM does not get a raw `Write` tool — `CreateAgent`/`EditAgent` are its only file-writing surface, keeping it scoped to agent definitions.

**Role boundary:** ARM writes agent `.md` files only. Developer writes Ruby code. CoS orchestrates when a task requires both (e.g. new agent + new custom tool).

**Depends on:** V9 (MergeBranchToSelf must exist).

**Not in V10:** ARM writing tool classes (Ruby files) — that remains Developer's domain.

**Tech Stack:** Rails 8.1, Minitest

---

## Implementation Plan

### Task 1: Make `CreateAgent`/`EditAgent` workspace-aware

Currently both tools default `@agents_dir` to `Rails.root.join("lib/daan/core/agents")`. When the ARM clones the self-repo into its workspace and calls `CreateAgent`, it needs to point at the clone's agents dir, not the running app's.

The tools already accept `agents_dir:` in `initialize` — verify this is wired through `Agent#tools` correctly. If not, ensure `agents_dir` is passed via the workspace path.

**Files:**
- Modify: `lib/daan/core/create_agent.rb` (verify/update `agents_dir` default logic)
- Modify: `lib/daan/core/edit_agent.rb` (same)
- Modify: `lib/daan/agent.rb` (pass `agents_dir` derived from workspace if needed)
- Create: `test/lib/daan/core/create_agent_workspace_test.rb`

**Step 1: Write failing test**

```ruby
# test/lib/daan/core/create_agent_workspace_test.rb
require "test_helper"

class CreateAgentWorkspaceTest < ActiveSupport::TestCase
  setup do
    @tmpdir = Dir.mktmpdir
    @agents_dir = File.join(@tmpdir, "lib/daan/core/agents")
    FileUtils.mkdir_p(@agents_dir)
  end

  teardown do
    FileUtils.rm_rf(@tmpdir)
    Daan::AgentRegistry.clear
  end

  test "CreateAgent writes to the provided agents_dir, not Rails.root" do
    tool = Daan::Core::CreateAgent.new(agents_dir: Pathname.new(@agents_dir))
    result = tool.execute(
      agent_name: "qa_engineer",
      display_name: "QA Engineer",
      description: "You run quality checks."
    )
    assert_match(/Successfully created/, result)
    assert File.exist?(File.join(@agents_dir, "qa_engineer.md"))
    refute File.exist?(Rails.root.join("lib/daan/core/agents/qa_engineer.md"))
  end

  test "EditAgent writes to the provided agents_dir, not Rails.root" do
    # Pre-create the agent file in @agents_dir
    File.write(File.join(@agents_dir, "qa_engineer.md"), <<~MD)
      ---
      name: qa_engineer
      display_name: QA Engineer
      model: claude-sonnet-4-20250514
      max_turns: 10
      ---
      You run quality checks.
    MD

    tool = Daan::Core::EditAgent.new(agents_dir: Pathname.new(@agents_dir))
    result = tool.execute(agent_name: "qa_engineer", display_name: "QA Lead")
    assert_match(/Successfully updated/, result)

    content = File.read(File.join(@agents_dir, "qa_engineer.md"))
    assert_includes content, "QA Lead"
  end
end
```

**Step 2: Run to confirm failures**

```
bin/rails test test/lib/daan/core/create_agent_workspace_test.rb
```

**Step 3: Update CreateAgent and EditAgent**

Ensure `@agents_dir` in both tools defaults to `Rails.root.join("lib/daan/core/agents")` only when no `agents_dir:` is passed. When an `agents_dir:` is provided (e.g. from workspace), use it directly.

No change needed if already working — the tests will confirm.

**Step 4: Run tests**

```
bin/rails test test/lib/daan/core/create_agent_workspace_test.rb
```

**Step 5: Run full suite**

```
bin/rails test && bin/rails test:system
```

**Step 6: Commit**

```bash
git add lib/daan/core/create_agent.rb lib/daan/core/edit_agent.rb \
        test/lib/daan/core/create_agent_workspace_test.rb
git commit -m "feat: CreateAgent/EditAgent accept agents_dir pointing at workspace clone"
```

---

### Task 2: ARM dev override + system prompt update

**Files:**
- Create: `config/agents/agent_resource_manager.md`

**Step 1: Create the dev override**

```markdown
---
name: agent_resource_manager
display_name: Agent Resource Manager
model: claude-sonnet-4-20250514
max_turns: 20
workspace: tmp/workspaces/agent_resource_manager
delegates_to: []
allowed_commands:
  - git
  - gh
tools:
  - Daan::Core::CreateAgent
  - Daan::Core::EditAgent
  - Daan::Core::Bash
  - Daan::Core::Read
  - Daan::Core::ReportBack
  - Daan::Core::MergeBranchToSelf
---
You are the Agent Resource Manager for the Daan agent team. You act as an HR manager for agents, responsible for creating and managing agent configurations.

{{include: partials/autonomy.md}}

Your primary responsibilities:
1. **Creating New Agents**: Use CreateAgent to define new agents with appropriate names, roles, tools, and delegation patterns
2. **Modifying Existing Agents**: Use EditAgent to update agent configurations safely
3. **Agent Architecture**: Understand the delegation hierarchy and ensure proper integration

When creating or editing agents:
- Choose descriptive but concise agent names (snake_case for internal name, Title Case for display)
- Assign appropriate tools based on the agent's role
- Set up proper delegation chains
- Create workspaces for agents that need file system access
- **Write system prompts that embed the autonomy principle**: use `{{include: partials/autonomy.md}}` in any new agent's prompt

When making changes to agent definitions, use the git workflow:
1. Bash: `[["gh", "repo", "clone", "<DAAN_SELF_REPO>", "daan-rails"]]` — clone the self repo into your workspace.
2. Use CreateAgent or EditAgent to write the agent definition into `daan-rails/lib/daan/core/agents/` within your workspace.
3. Bash: `[["git", "add", "-A"], ["git", "commit", "-m", "<message>"]]` with path set to `daan-rails` — stage and commit.
4. Bash: `[["git", "push", "origin", "<branch-name>"]]` — push the branch.
5. **In development (you have MergeBranchToSelf):** Call MergeBranchToSelf with the branch name — merges into develop and reloads agent definitions immediately.
6. **In production (no MergeBranchToSelf):** Bash: `[["gh", "pr", "create", "--title", "<title>", "--body", "<body>", "--base", "main"]]` — open a PR.
7. ReportBack with the outcome.

Always ensure agents fit properly into the existing hierarchy and have the tools they need to perform their roles effectively.
```

**Step 2: Run full suite**

```
bin/rails test && bin/rails test:system
```

**Step 3: Commit**

```bash
git add config/agents/agent_resource_manager.md
git commit -m "feat: dev override for ARM — git access and MergeBranchToSelf for agent definition self-modification"
```

---

## Demo Script

**Prerequisites:** V9 complete. `develop` branch exists on `DAAN_SELF_REPO`. `GITHUB_TOKEN` set.

1. Start the app: `bin/dev`
2. Message the CoS: *"Please add a new QA Engineer agent to the team. They should be able to read files and report back."*
3. Watch the CoS delegate to the ARM.
4. Watch the ARM thread:
   - `gh repo clone ramontayag/daan-rails daan-rails`
   - `git checkout -b feature/add-qa-engineer`
   - `CreateAgent` — writes `lib/daan/core/agents/qa_engineer.md` in the clone
   - `git add -A` + `git commit`
   - `git push origin feature/add-qa-engineer`
   - `MergeBranchToSelf('feature/add-qa-engineer')`
   - `ReportBack`
5. Refresh the app — QA Engineer appears in the agent sidebar immediately.
6. Ask CoS: *"Who is on your team?"* — CoS calls `ListAgents` and QA Engineer is listed.
