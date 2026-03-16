# Development Workflow

## Test first

Write tests before implementation. Red-green-refactor:
1. Write a failing test for the behavior you want
2. Write the minimum code to make it pass
3. Refactor if needed

## Running tests

Always run:

```
bin/rails test && bin/rails test:system
```

Never use `bin/rails test` alone — it skips system tests.

## Task execution rhythm

After completing each task:
1. Stop and present what was done
2. User reviews the code (via `/review uncommitted` or inline)
3. Address any review comments
4. Commit
5. Move to next task

Do not chain multiple tasks together without stopping for review.

## Agent Self-Modification Workflow

When modifying agent definitions or core tools:

### Development Mode
1. Create feature branch: `git checkout -b feature/my-enhancement`
2. Make changes to agent files or tools
3. Commit changes: `git add -A && git commit -m "Description"`
4. **CRITICAL: Push to GitHub origin**: `git push origin feature/my-enhancement`
5. Use PromoteBranch tool: merges branch into develop and hot-reloads agent definitions
6. Changes are live immediately — open a PR later when ready for production

### Production Mode
1. Create feature branch and make changes
2. Push to GitHub origin: `git push origin feature/my-enhancement`
3. Use PromoteBranch tool: opens a PR against main

### PromoteBranch Requirements
- **Branch must exist in GitHub origin** before calling the tool
- Tool validates branch exists and provides clear error if not
- Handles already-merged branches gracefully
- In development: automatically reloads agent definitions after merge

### Common Mistakes to Avoid
- ❌ Calling PromoteBranch on local-only branches (not pushed to GitHub)
- ❌ Forgetting to push feature branches to origin
- ✅ Always push first, then call PromoteBranch

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

## Optional injection for ViewComponents (Lookbook pattern)

When a component needs an associated record (e.g. a tool result message), accept
it as an optional keyword param and fall back to a DB lookup only when not provided:

```ruby
def initialize(tool_call:, result: nil)
  @tool_call = tool_call
  @result = result
end

def result = @result || Message.find_by(tool_call_id: tool_call.id)&.content
```

Lookbook previews pass the value directly (`result: "Hello, world!"`) so no extra
DB query fires during rendering. Production callers omit the param and get the lazy
lookup. Use `find_or_create_by!` (not `create!`) in previews to avoid uniqueness
errors on repeated renders.

## lib/ is a future gem — respect the boundary

`lib/daan/core/` will be extracted as a standalone gem. Do not couple `config/`
(deployment layer) to `lib/` internals.

- Override files in `config/agents/` must be self-contained — inline partial
  content rather than using `{{include:}}` pointing into `lib/`
- Never symlink `config/` paths into `lib/`
- Agent partials under `lib/daan/core/agents/partials/` are gem internals

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