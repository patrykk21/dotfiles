---
name: merge-base
description: "Merge the base branch into the current branch and resolve any conflicts. Used by the autopilot scheduler when a PR has conflicts."
---

# Merge Base Branch

Merge the PR's base branch into the current branch to resolve conflicts.

## Steps

1. **Identify the base branch** — check what branch this PR targets:
   ```bash
   gh pr view --json baseRefName -q '.baseRefName'
   ```
   If no PR exists for this branch, fall back to the project's default base branch.

2. **Fetch latest**:
   ```bash
   git fetch origin
   ```

3. **Merge the base branch**:
   ```bash
   git merge origin/<base_branch>
   ```

4. **If there are conflicts**, resolve them:
   - Read each conflicted file (`git diff --name-only --diff-filter=U`)
   - For each file, understand both sides of the conflict
   - Resolve intelligently — keep the intent of both changes where possible
   - Stage resolved files: `git add <file>`

5. **Complete the merge**:
   ```bash
   git commit --no-edit
   ```

6. **Run verification** — ensure the merge didn't break anything:
   - Run typecheck, lint, and tests if available
   - Fix any issues introduced by the merge

7. **Push**:
   ```bash
   git push
   ```

## Rules
- Do NOT force push — this is a merge, not a rebase
- Do NOT modify files beyond what's needed for conflict resolution
- If a conflict is too complex to resolve confidently, set the state marker to `needs_input|Complex merge conflict in <file> — need guidance` and stop
