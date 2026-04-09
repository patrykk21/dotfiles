---
description: "Create a new git worktree with a tmux session. Usage: /new-worktree <ticket-name> [--from <branch>]"
allowed-tools: ["Bash"]
---

# New Worktree

Create a git worktree using the tmux worktree script. Sets up a proper tmux session with 3 windows (claude/server/commands), copies env files, and installs dependencies.

## Parse Arguments

Arguments: `$ARGUMENTS`

Extract:
- `TICKET` — first token (required). This is the branch/worktree name (e.g. `ECH-123-fix-thing`, `PROJ-42-new-feature`)
- `BASE_BRANCH` — value after `--from` flag (optional)

If `TICKET` is missing, tell the user the usage and stop:
```
Usage: /new-worktree <ticket-name> [--from <branch>]

Examples:
  /new-worktree ECH-123-fix-auth
  /new-worktree PROJ-42-new-feature --from develop
```

## Detect Base Branch (if --from not provided)

Run from the main repo root (use `git worktree list | head -1 | awk '{print $1}'` to find it):

```bash
git -C "$(git worktree list | head -1 | awk '{print $1}')" branch -a --format='%(refname:short)' | sed 's|origin/||' | sort -u
```

Pick the first match from this priority list that exists as a local or remote branch:
1. `main-do`
2. `main`
3. `master`
4. `develop`
5. Current branch (fallback)

Tell the user which base branch was detected.

## Verify We're in a Git Repo

```bash
git worktree list | head -1
```

If this fails, tell the user they need to run this from inside a git repository.

## Run the Worktree Script

```bash
~/.config/tmux/scripts/worktree-create.sh "$TICKET" "$BASE_BRANCH"
```

The script will:
- Create the worktree at `~/worktrees/<repo-name>/<ticket>/`
- Create a tmux session named `<ticket>` with 3 windows
- Copy `.env*` files and `.claude/` from the main repo
- Install dependencies (auto-detects bun/yarn/pnpm/npm)
- Switch your tmux client to the new session

## Report Result

On success:
```
✓ Worktree created: ~/worktrees/<repo>/<ticket>/
✓ Branch: <ticket> (from <base-branch>)
✓ Tmux session: <ticket> — switching now
```

On failure, show the error and suggest fixes (e.g. branch already exists, not in a git repo).
