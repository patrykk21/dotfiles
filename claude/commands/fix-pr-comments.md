---
description: Fetch open PR review comments for the current branch, triage which ones make sense to act on, and fix them
allowed-tools: Bash, Read, Edit, MultiEdit, Write, Grep, Glob, mcp__github-work__get_pull_request, mcp__github-work__list_pull_requests, mcp__github-work__get_pull_request_comments, mcp__github-work__get_pull_request_reviews, mcp__github-work__add_issue_comment, mcp__github-personal__get_pull_request, mcp__github-personal__list_pull_requests, mcp__github-personal__get_pull_request_comments, mcp__github-personal__get_pull_request_reviews
---

# Fix PR Comments

Fetch all open/unresolved review comments on the current branch's PR, triage them, and fix the actionable ones.

Usage:
- `/fix-pr-comments` — auto-detect PR from current branch, fix all actionable comments
- `/fix-pr-comments --dry-run` — triage only, show what would be fixed without making changes
- `/fix-pr-comments --comment` — post a reply comment on the PR after fixing

Arguments: $ARGUMENTS

## WORKFLOW

### STEP 1 — Detect the PR

1. Run `git rev-parse --abbrev-ref HEAD` to get the current branch name.
2. Run `git remote -v` to determine the remote repo (owner/repo).
3. Determine whether this is a work repo (`github-work`) or personal (`github-personal`):
   - Work: repos under `Work/` path or matching the org (e.g. Groupon)
   - Personal: everything else
4. Use the appropriate GitHub MCP (`github-work` or `github-personal`) to find the open PR for this branch via `list_pull_requests` filtered by `head` branch.
5. If no PR found, inform the user and stop.

### STEP 2 — Fetch all review comments

Fetch in parallel:
- **Review thread comments** via `get_pull_request_reviews` (includes review body + state)
- **Inline code comments** via `get_pull_request_comments` (line-level comments)

Filter to only **unresolved/open** comments:
- For reviews: state is `CHANGES_REQUESTED` or `COMMENTED` (not `APPROVED` and not `DISMISSED`)
- For inline comments: include all (GitHub doesn't expose resolved state via API — treat all as candidates)

### STEP 3 — Triage comments

For each comment, classify it into one of:
- ✅ **ACTIONABLE** — Clear code change requested (naming, refactor, bug, missing logic, style)
- ⚠️ **DISCUSSION** — Opinion, question, or debate — no clear action, skip
- ❌ **SKIP** — Nitpick marked `nit:`, already addressed, or out of scope

Use this judgment:
- If the reviewer asks "why not X?" with no clear preference → DISCUSSION
- If the reviewer says "rename this to X", "extract this", "this will cause Y bug" → ACTIONABLE
- If comment starts with `nit:` or `optional:` → SKIP (unless --fix-nits flag passed)
- If comment references a line that no longer exists in the diff → SKIP

Print the triage table before making any changes:

```
## PR Comment Triage

| # | File | Line | Author | Status | Action |
|---|------|------|--------|--------|--------|
| 1 | src/foo.ts | 42 | @alice | ✅ ACTIONABLE | Rename variable to `userId` |
| 2 | src/bar.ts | 17 | @bob | ⚠️ DISCUSSION | Asked about approach — skipping |
| 3 | src/baz.ts | 88 | @carol | ❌ SKIP | Nit about formatting |
```

If `--dry-run` is passed, stop here.

### STEP 4 — Fix actionable comments

For each ACTIONABLE comment:
1. Read the relevant file(s)
2. Understand the full context around the flagged line
3. Apply the fix — be surgical, change only what the comment asks for
4. Do not refactor unrelated code while fixing

Handle common comment types:
- **Rename**: use MultiEdit to rename across the file
- **Extract function/component**: create the abstraction, update call sites
- **Missing null check / guard**: add the defensive code
- **Wrong type**: fix the TypeScript type
- **Logic bug**: fix the logic as described
- **Style/formatting**: apply the change

After all fixes, run:
```bash
# If TypeScript project
npx tsc --noEmit 2>&1 | head -30

# If there's a lint script
npm run lint 2>&1 | head -30 || bun run lint 2>&1 | head -30
```

Fix any type errors introduced by your changes.

### STEP 5 — Summary

Print a summary of what was done:

```
## Fix Summary

Fixed 3 of 5 comments:

✅ src/foo.ts:42 — Renamed `uid` → `userId` (@alice)
✅ src/api/users.ts:103 — Added null guard before `.map()` (@bob)
✅ src/components/Card.tsx:28 — Extracted `renderHeader()` into separate component (@carol)

Skipped:
⚠️ src/bar.ts:17 — Discussion about caching approach (no clear action)
❌ src/baz.ts:88 — Nit about spacing (use --fix-nits to include)
```

If `--comment` flag is passed, post this summary as a reply comment on the PR using `add_issue_comment`.

## GUIDELINES

- Be conservative: when in doubt, skip rather than guess intent
- Never change logic that wasn't mentioned in a comment
- If a fix would require understanding business context you don't have, mark it DISCUSSION
- Respect the reviewer's exact wording — if they said "rename to X", use exactly X
- After fixing, do not stage or commit — leave that to the user
- **Every unaddressed comment MUST get a reply** — for DISCUSSION and SKIP comments, post a reply on the PR thread explaining why it wasn't actioned (e.g., "This is a design choice because...", "Skipping this nit for now — will address in a follow-up", "This line no longer exists after the refactor"). Never leave a reviewer's comment without a response.
