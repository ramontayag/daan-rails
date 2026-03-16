# Daan Rails

An AI agent team management platform built with Rails.

<<<<<<< HEAD
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

# Architecture

This repo is the **reference deployment** for the Daan agent platform. It is structured in three layers that will eventually be separated:

- **`lib/daan/core/`** — agent runtime (loader, registry, tools, memory). Will become the `daan-core` gem.
- **`lib/daan/chat/`** — Slack-like chat UI engine. Will become the `daan-ui` Rails engine.
- **`config/agents/`** — deployment-level agent overrides (this repo only).

Keep `config/` and `app/` free of direct references to `lib/daan/core/` internals. The boundary between the future gem and the deployment app should stay clean now, so extraction is painless later.

# Setup
=======
## Setup
>>>>>>> feature/sidebar-highlighting-bug-fix

Fill out the `.env.local` file:

```bash
cp .env{,.local}
```

| Variable | Required | Description |
|----------|----------|-------------|
| `ANTHROPIC_API_KEY` | Yes | Anthropic API key for LLM calls |
| `DAAN_SELF_REPO` | No | GitHub repo this app lives in (e.g. `ramontayag/daan-rails`). When set, agents with a workspace know what repo to clone when asked to modify the team or themselves. |

## Development

### Running the Application

```bash
bin/dev
```

### Tests

```bash
bin/rails test
bin/rails test:system
```

### Code Style

```bash
bin/rubocop
```

## Contributing

### Commit Message Format

This project uses [Conventional Commits](https://www.conventionalcommits.org/) for commit messages and pull request titles.

**Format:** `<type>[optional scope]: <description>`

**Examples:**
- `feat: add agent delegation feature`
- `fix: resolve memory leak in conversation runner`
- `docs: update README with setup instructions`
- `refactor: simplify CI workflow`
- `test: add integration tests for agent creation`

**Types:**
- `feat`: new feature
- `fix`: bug fix
- `docs`: documentation changes
- `style`: code style changes (formatting, etc.)
- `refactor`: code refactoring
- `test`: adding or modifying tests
- `chore`: maintenance tasks, dependency updates

**Pull Request Titles:**
Use the same conventional commit format for PR titles. The title will become the commit message when squash-merged.

### Code Quality

- All code must pass RuboCop linting
- Tests are required for new features
- Follow Rails conventions and best practices