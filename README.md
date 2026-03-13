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
