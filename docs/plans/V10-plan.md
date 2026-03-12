---
shaping: true
---

# V10: ARM Self-Modifies Agent Definitions

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** The Agent Resource Manager can create and edit agent definitions through git — cloning `DAAN_SELF_REPO` into its workspace, using `CreateAgent`/`EditAgent` to write into the clone, committing, pushing, and (in dev) merging immediately via `MergeBranchToSelf`. In production it opens a PR to `main`.

**Architecture:**
- `CreateAgent` / `EditAgent` — gain an optional `agents_dir` param on `execute` (workspace-relative path, e.g. `"daan-rails/lib/daan/core/agents"`). When provided, the tool resolves it against the workspace and writes there. It also skips `AgentRegistry.register` in this case — registration happens later via `AgentLoader.sync!` inside `MergeBranchToSelf`. When absent, both tools behave exactly as today (write to `Rails.root.join("lib/daan/core/agents")`, register immediately). No changes to `agent.rb` or `initialize` signatures.
- `config/agents/agent_resource_manager.md` — dev override that adds `allowed_commands: [git, gh]`, `Daan::Core::Bash`, and `Daan::Core::MergeBranchToSelf`. Explicitly drops the base definition's `Daan::Core::Write` — ARM file-writing surface is `CreateAgent`/`EditAgent` only, keeping it scoped to agent definitions.
- ARM system prompt — updated with git-based workflow. References the team repo from workspace instructions (injected by `AgentLoader` from `DAAN_SELF_REPO` env var) rather than a hardcoded placeholder.

**Role boundary:** ARM writes agent `.md` files only. Developer writes Ruby code. CoS orchestrates when a task requires both (e.g. new agent + new custom tool: Developer adds tool first, then ARM creates the agent).

**Depends on:** V9 (MergeBranchToSelf must exist, `config/agents/` loading must exist).

**Not in V10:** ARM writing tool classes (Ruby files) — Developer's domain.

**Tech Stack:** Rails 8.1, Minitest

---

## Implementation Plan

### Task 1: Make CreateAgent/EditAgent clone-aware

Add an optional `agents_dir` param to `execute` in both tools. When the ARM calls `CreateAgent(agents_dir: "daan-rails/lib/daan/core/agents", ...)`, the tool writes into the workspace clone and skips registry registration. Absent param → existing behavior unchanged.

**Files:**
- Modify: `lib/daan/core/create_agent.rb`
- Modify: `lib/daan/core/edit_agent.rb`
- Create: `test/lib/daan/core/create_agent_clone_test.rb`

**Step 1: Write failing tests**

```ruby
# test/lib/daan/core/create_agent_clone_test.rb
require "test_helper"

class CreateAgentCloneTest < ActiveSupport::TestCase
  setup do
    @workspace_dir = Dir.mktmpdir
    @workspace = Daan::Workspace.new(@workspace_dir)
    @agents_dir = File.join(@workspace_dir, "daan-rails/lib/daan/core/agents")
    FileUtils.mkdir_p(@agents_dir)
  end

  teardown do
    FileUtils.rm_rf(@workspace_dir)
  end

  # --- CreateAgent ---

  test "CreateAgent writes to workspace-relative agents_dir when provided" do
    tool = Daan::Core::CreateAgent.new(workspace: @workspace)
    tool.execute(
      agent_name: "qa_engineer",
      display_name: "QA Engineer",
      description: "You run quality checks.",
      agents_dir: "daan-rails/lib/daan/core/agents"
    )
    assert File.exist?(File.join(@agents_dir, "qa_engineer.md"))
  end

  test "CreateAgent does NOT register agent when agents_dir is provided" do
    tool = Daan::Core::CreateAgent.new(workspace: @workspace)
    tool.execute(
      agent_name: "qa_engineer",
      display_name: "QA Engineer",
      description: "You run quality checks.",
      agents_dir: "daan-rails/lib/daan/core/agents"
    )
    assert_nil Daan::AgentRegistry.find("qa_engineer")
  end

  test "CreateAgent writes to Rails.root and registers when agents_dir is absent" do
    tool = Daan::Core::CreateAgent.new(workspace: @workspace)
    agent_file = Rails.root.join("lib/daan/core/agents/test_clone_agent.md")
    tool.execute(
      agent_name: "test_clone_agent",
      display_name: "Test Clone Agent",
      description: "Temporary test agent."
    )
    assert agent_file.exist?
    assert_not_nil Daan::AgentRegistry.find("test_clone_agent")
  ensure
    agent_file&.delete if agent_file&.exist?
  end

  # --- EditAgent ---

  test "EditAgent writes to workspace-relative agents_dir when provided" do
    File.write(File.join(@agents_dir, "qa_engineer.md"), <<~MD)
      ---
      name: qa_engineer
      display_name: QA Engineer
      model: claude-sonnet-4-20250514
      max_turns: 10
      ---
      You run quality checks.
    MD

    tool = Daan::Core::EditAgent.new(workspace: @workspace)
    tool.execute(
      agent_name: "qa_engineer",
      display_name: "QA Lead",
      agents_dir: "daan-rails/lib/daan/core/agents"
    )

    content = File.read(File.join(@agents_dir, "qa_engineer.md"))
    assert_includes content, "QA Lead"
  end

  test "EditAgent does NOT register agent when agents_dir is provided" do
    File.write(File.join(@agents_dir, "qa_engineer.md"), <<~MD)
      ---
      name: qa_engineer
      display_name: QA Engineer
      model: claude-sonnet-4-20250514
      max_turns: 10
      ---
      You run quality checks.
    MD

    tool = Daan::Core::EditAgent.new(workspace: @workspace)
    tool.execute(
      agent_name: "qa_engineer",
      display_name: "QA Lead",
      agents_dir: "daan-rails/lib/daan/core/agents"
    )

    assert_nil Daan::AgentRegistry.find("qa_engineer")
  end

  test "EditAgent does NOT create workspace dirs when agents_dir is provided" do
    File.write(File.join(@agents_dir, "qa_engineer.md"), <<~MD)
      ---
      name: qa_engineer
      display_name: QA Engineer
      model: claude-sonnet-4-20250514
      max_turns: 10
      ---
      You run quality checks.
    MD

    tool = Daan::Core::EditAgent.new(workspace: @workspace)
    tool.execute(
      agent_name: "qa_engineer",
      workspace: "tmp/workspaces/qa_engineer",
      agents_dir: "daan-rails/lib/daan/core/agents"
    )

    refute Rails.root.join("tmp/workspaces/qa_engineer").exist?
  end
end
```

**Step 2: Run to confirm failures**

```
bin/rails test test/lib/daan/core/create_agent_clone_test.rb
```

**Step 3: Update CreateAgent**

Add `agents_dir` as an optional `execute` param. When provided, resolve against `@workspace` and skip registry registration.

```ruby
param :agents_dir, desc: "Workspace-relative path to the agents directory in a cloned repo " \
                         "(e.g. 'daan-rails/lib/daan/core/agents'). Omit when modifying the " \
                         "running app directly.", required: false

def execute(agent_name:, display_name:, description:, tools: nil, delegates_to: nil,
            workspace: nil, model: nil, max_turns: nil, agents_dir: nil)
```

Inside `execute`, replace the `agents_dir = @agents_dir` line with:

```ruby
agents_dir = agents_dir ? @workspace.resolve(agents_dir) : @agents_dir
writing_to_clone = agents_dir != @agents_dir
```

Replace the registration block at the end:

```ruby
agent_file.write(content)

return "Successfully created agent '#{agent_name}' (#{display_name})" if writing_to_clone

begin
  definition = Daan::AgentLoader.parse(agent_file)
  agent = Daan::Agent.new(**definition)
  Daan::AgentRegistry.register(agent)
  "Successfully created agent '#{agent_name}' (#{display_name})"
rescue => e
  agent_file.delete if agent_file.exist?
  "Error: Failed to register agent - #{e.message}"
end
```

**Step 4: Update EditAgent**

Add the same `agents_dir` param to `execute`. When provided:
- Resolve the target file against the workspace path
- Skip workspace directory creation/cleanup (those dirs are on `Rails.root`, irrelevant for clones)
- Skip registry registration

```ruby
param :agents_dir, desc: "Workspace-relative path to the agents directory in a cloned repo " \
                         "(e.g. 'daan-rails/lib/daan/core/agents'). Omit when modifying the " \
                         "running app directly.", required: false

def execute(agent_name:, display_name: nil, description: nil, tools: nil, delegates_to: nil,
            workspace: nil, model: nil, max_turns: nil, agents_dir: nil)
```

Inside `execute`, derive the target dir and a `writing_to_clone` flag the same way as `CreateAgent`. Use the resolved dir for `agent_file_path`. Gate workspace dir creation on `!writing_to_clone`. Gate registry registration on `!writing_to_clone`.

**Step 5: Run tests**

```
bin/rails test test/lib/daan/core/create_agent_clone_test.rb
```

**Step 6: Run full suite**

```
bin/rails test && bin/rails test:system
```

**Step 7: Commit**

```bash
git add lib/daan/core/create_agent.rb lib/daan/core/edit_agent.rb \
        test/lib/daan/core/create_agent_clone_test.rb
git commit -m "feat: CreateAgent/EditAgent accept agents_dir on execute — write into workspace clone without registering"
```

---

### Task 2: ARM dev override + system prompt update

**Files:**
- Create: `config/agents/agent_resource_manager.md`

**Step 1: Create the dev override**

Note: `Daan::Core::Write` is intentionally omitted — the ARM's only file-writing surface in this override is `CreateAgent`/`EditAgent`, keeping it scoped to agent definitions. The DAAN_SELF_REPO value is already injected into the system prompt by `AgentLoader#workspace_instructions` — the prompt references "the team repo" rather than a hardcoded placeholder. `max_turns` is raised to 15 (from 10) to accommodate the 8-step git workflow: clone, checkout, CreateAgent/EditAgent, add, commit, push, MergeBranchToSelf, ReportBack.

```markdown
---
name: agent_resource_manager
display_name: Agent Resource Manager
model: claude-sonnet-4-20250514
max_turns: 15
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
1. Bash: `[["gh", "repo", "clone", "<team-repo-url>", "daan-rails"]]` — the team repo URL is provided in your workspace instructions. Clone it into your workspace.
2. Bash: `[["git", "checkout", "-b", "<branch-name>"]]` with path set to `daan-rails` — create your working branch.
3. Use CreateAgent or EditAgent with `agents_dir: "daan-rails/lib/daan/core/agents"` to write the agent definition into the clone.
4. Bash: `[["git", "add", "-A"], ["git", "commit", "-m", "<message>"]]` with path set to `daan-rails`.
5. Bash: `[["git", "push", "origin", "<branch-name>"]]` with path set to `daan-rails`. Authentication is handled automatically by `gh repo clone`. Do not run `gh auth login` — it requires interactive input and will time out.
6. **In development (you have MergeBranchToSelf):** Call MergeBranchToSelf with the branch name — merges into develop and reloads agent definitions immediately.
7. **In production (no MergeBranchToSelf):** Bash: `[["gh", "pr", "create", "--title", "<title>", "--body", "<body>", "--base", "main"]]` with path set to `daan-rails`.
8. ReportBack with the outcome.

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
   - `gh repo clone <DAAN_SELF_REPO> daan-rails`
   - `git checkout -b feature/add-qa-engineer`
   - `CreateAgent` with `agents_dir: "daan-rails/lib/daan/core/agents"` — writes `qa_engineer.md` into the clone
   - `git add -A` + `git commit`
   - `git push origin feature/add-qa-engineer`
   - `MergeBranchToSelf('feature/add-qa-engineer')`
   - `ReportBack`
5. Refresh the app — QA Engineer appears in the agent sidebar immediately.
6. Ask CoS: *"Who is on your team?"* — CoS calls `ListAgents` and QA Engineer is listed.
