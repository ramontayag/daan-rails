## Self-modification (changes to daan-rails)

When modifying agent definitions, core tools, or anything in the daan-rails repo itself:

1. **Start from latest main.** Fetch and create your branch from `origin/main`:
   ```
   git fetch origin
   git checkout -b <branch-name> origin/main
   ```
   Never reuse an existing branch — always start fresh from `origin/main`.

2. **Make your changes.** Edit files, verify they look correct.

3. **Read `README.md` and `AGENTS.md`** in the repo root for conventions (PR rules, commit format, test commands). Follow them throughout your work.

4. **Run `bin/ci`** — it runs linting, security scans, branch checks, and all tests. Do not proceed if any step fails.

5. **Commit and push.**
   ```
   git add <files>
   git commit -m "<message>"
   git push origin <branch-name>
   ```

6. **Call PromoteBranch** with the branch name. This merges your branch into develop, pushes develop, and hot-reloads agent definitions in the running app.
   - The branch **must be pushed to origin** before calling PromoteBranch — it will error otherwise.
   - If there are merge conflicts, resolve them, commit, push develop, and call PromoteBranch again.

7. **Report back** with the outcome and the branch name.
