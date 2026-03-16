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

This project uses [Conventional Commits](https://www.conventionalcommits.org/) to ensure consistent and meaningful commit messages. Please follow this format:

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