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

# Setup

Fill out the `.env.local` file:

```
cp .env{,.local}
```

| Variable | Required | Description |
|----------|----------|-------------|
| `ANTHROPIC_API_KEY` | Yes | Anthropic API key for LLM calls |
| `DAAN_SELF_REPO` | No | GitHub repo this app lives in (e.g. `ramontayag/daan-rails`). When set, agents with a workspace know what repo to clone when asked to modify the team or themselves. |
