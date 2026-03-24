# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...

# Coding Conventions

## Testing: tools yes, agents no

Tools (`lib/daan/core/*.rb`) need unit tests — they contain logic. Agent `.md` files are just configuration (YAML frontmatter + system prompt) and don't need their own tests. Writing to the real `lib/daan/core/agents/` directory in tests causes race conditions with parallel test runs.

## Scopes use Arel, not SQL strings

Scopes must use Arel node methods rather than raw SQL strings. This keeps them composable and mergeable, and avoids SQL injection risk.

```ruby
scope :since_id,            ->(id)      { where(arel_table[:id].gt(id)) }
scope :where_created_at_gt, ->(time)    { where(arel_table[:created_at].gt(time)) }
scope :where_content_like,  ->(pattern) { where(arel_table[:content].matches(pattern)) }
```

Not:

```ruby
scope :since_id, ->(id) { where("id > ?", id) }
```

## Seam injection

Constructor parameters that have smart defaults derived from other passed objects, but can be overridden by callers. The component (or service) resolves what it needs from available context; tests and Lookbook can inject substitutes without changing production call sites.

Example in a ViewComponent:

```ruby
def initialize(message:, chat: nil, agent_display_name: nil)
  @message            = message
  @chat               = chat
  @agent_display_name = agent_display_name
end

def chat = @chat ||= message.chat
def agent_display_name = @agent_display_name ||= chat.agent.display_name
```

Production callers just pass `message:`. Tests and Lookbook pass whatever they need to override.

## Name time constants with their unit

Constants that represent durations must include the unit in the name: `DEFAULT_TIMEOUT_SECONDS`, `POLL_INTERVAL_MS`, etc. Bare names like `DEFAULT_TIMEOUT` are ambiguous.

# Architecture

This repo is the **reference deployment** for the Daan agent platform. It is structured in three layers that will eventually be separated:

- **`lib/daan/core/`** — agent runtime (loader, registry, tools, memory). Will become the `daan-core` gem.
- **`lib/daan/chat/`** — Slack-like chat UI engine. Will become the `daan-ui` Rails engine.
- **`config/agents/`** — deployment-level agent overrides (this repo only).

Keep `config/` and `app/` free of direct references to `lib/daan/core/` internals. The boundary between the future gem and the deployment app should stay clean now, so extraction is painless later.

# Setup

Fill out the `.env.local` file:

```
cp .env{,.local}
```

| Variable | Required | Description |
|----------|----------|-------------|
| `ANTHROPIC_API_KEY` | Yes | Anthropic API key for LLM calls |
| `DAAN_SELF_REPO` | No | GitHub repo this app lives in (e.g. `ramontayag/daan-rails`). When set, agents with a workspace know what repo to clone when asked to modify the team or themselves. |

# Development

## Commit Conventions

This project uses [Conventional Commits](https://www.conventionalcommits.org/) for both **commit messages** and **pull request titles**. Please follow this format:

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

### Types
- **feat**: A new feature
- **fix**: A bug fix
- **docs**: Documentation only changes
- **style**: Changes that do not affect the meaning of the code (white-space, formatting, etc.)
- **refactor**: A code change that neither fixes a bug nor adds a feature
- **test**: Adding missing tests or correcting existing tests
- **chore**: Changes to the build process or auxiliary tools and libraries

### Examples
```
feat(ui): add new message input component
fix(sidebar): resolve agent highlighting on thread URLs
docs(readme): add conventional commit guidelines
test(components): add tests for AgentItemComponent
refactor(tools): extract common tool validation logic
chore(deps): update Rails to 7.1.2
```

### Scope (Optional)
Common scopes include:
- **ui**: User interface components and styling
- **api**: API-related changes
- **tools**: Agent tools and functionality
- **core**: Core agent runtime
- **config**: Configuration changes
- **deps**: Dependencies

## Pull Requests

PRs must always be from a feature or fix branch (e.g. `feat/*`, `fix/*`) against `main`. Never open a PR from `develop` to `main`.

## Clean Commits

PRs should have clean, logical commits. Each commit should represent a single coherent change.

If you make a follow-up commit that fixes something introduced in a previous commit on the same branch, **fixup** that commit rather than leaving a separate "fix typo" or "oops" commit.

### Examples

**Bad** — follow-up commits that should have been fixups:

```
a1b2c3d feat(ui): add compose bar autofocus parameter
f4e5d6c fix: forgot to update the test
9g8h7i6 fix: actually pass the parameter in the template
```

**Good** — the fixes are squashed into the original commit:

```
a1b2c3d feat(ui): add compose bar autofocus parameter
```

**Also good** — multiple commits that each stand on their own:

```
a1b2c3d refactor(ui): extract autofocus logic into parameter
b2c3d4e feat(ui): disable autofocus when thread panel is open
```

### How to fixup

```bash
# Stage your fix
git add app/components/compose_bar_component.rb

# Fixup the commit that introduced the issue
git commit --fixup <commit-sha>

# Autosquash to fold it in (rebase onto the commit before the one you're fixing)
git rebase -i --autosquash main
```