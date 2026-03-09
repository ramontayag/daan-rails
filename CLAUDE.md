# Development Workflow

## Task execution rhythm

After completing each task:
1. Stop and present what was done
2. User reviews the code (via `/review uncommitted` or inline)
3. Address any review comments
4. Commit
5. Move to next task

Do not chain multiple tasks together without stopping for review.

## Let it crash

Write for the happy path. Don't add defensive guards for inputs that can't
arrive if the UI is correct. If something unexpected slips through, let Rails
catch it and return a 500 — don't silently swallow edge cases with rescue
blocks or early returns. Trust the framework.

## Models are narrow

Models should not reach out to jobs, services, or external systems. Avoid
model callbacks (`after_create_commit`, `after_save`, etc.) that have effects
beyond the model itself (enqueueing jobs, sending broadcasts, calling services).

Put that logic in the controller or service that owns the action instead.

This includes Turbo Stream broadcasts that render components — those are not
trivial notifications; they do real work. They belong in the caller.

## Single place to create a resource

If a resource is created in more than one place, extract a service that is
the only place it is created. Any side effects (broadcasts, job enqueueing)
live in that service, not in the model.

Example: `Daan::CreateMessage` is the only place `Message` records are
created. It handles creation and the Turbo Stream broadcast together.

## Jobs are thin wrappers around services

Jobs call a service and nothing else. The service holds all logic.

- **Service** (`lib/daan/` or `app/services/`): unit tests with stubs, covers all branches
- **Job** (`app/jobs/`): one golden-path integration test using VCR (real API call recorded once)

Example:
```ruby
class LlmJob < ApplicationJob
  def perform(chat)
    Daan::ConversationRunner.call(chat)
  end
end
```
