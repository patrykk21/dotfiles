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

You MUST fetch from BOTH sources. Do NOT skip either one.

**Source A: Review bodies** (CRITICAL — most human reviewers write feedback here, not as inline comments):
```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews --paginate \
  --jq '[.[] | select(.state == "CHANGES_REQUESTED" or .state == "COMMENTED") | select(.body != null and .body != "") | {id: .id, author: .user.login, state: .state, body: .body, submitted_at: .submitted_at}]'
```
**IMPORTANT**: You MUST use `--paginate` because PRs with many CodeRabbit reviews can exceed the default 30-per-page limit, causing the latest human reviews to be on page 2+.
This returns reviews with substantive body text. These often contain numbered issues like `[C1]`, `[I1]`, `### Critical`, `### Important` etc. **Each issue in the body is a separate comment to triage.**

**Source B: Inline thread comments** (code-level comments attached to specific lines):
```bash
gh api graphql -f query='{ repository(owner: "{owner}", name: "{repo}") { pullRequest(number: {pr_number}) { reviewThreads(first: 100) { nodes { isResolved comments(first: 10) { nodes { body author { login } path line } } } } } } }'
```
Filter to unresolved threads only.

**IMPORTANT**:
- If Source A returns reviews with body text, those MUST be triaged even if Source B returns zero inline comments.
- When a reviewer has multiple reviews, triage the **latest** one from each reviewer (by `submitted_at`). Earlier reviews may have been addressed already — but the latest one reflects what the reviewer currently wants fixed.
- A `COMMENTED` review with substantive issues (numbered items, file references, code suggestions) is just as actionable as `CHANGES_REQUESTED` — the reviewer chose "comment" instead of "request changes" but still expects fixes.

### STEP 3 — Triage comments

There are TWO sources of feedback to triage:

#### 3a. Review body comments

Reviews with state `CHANGES_REQUESTED` or `COMMENTED` may contain structured feedback **in the review body itself** (not attached to any code line). These are common when reviewers write summary reviews with numbered issues (e.g., "[C1] No rate limiting", "[I1] Misleading column name").

Parse the review body for actionable items. Look for:
- Numbered/labeled issues (e.g., `### Critical`, `**[C1]**`, `### Important`, `**[I1]**`)
- Bullet points describing specific code changes needed
- File paths and code suggestions in the body text

Include these in the triage table with "Review body" as the File column.

#### 3b. Inline code comments

Line-level comments attached to specific files and lines.

#### Classification

For each comment (from body or inline), classify it into one of:
- ✅ **ACTIONABLE** — Clear code change requested (naming, refactor, bug, missing logic, style)
- ⚠️ **DISCUSSION** — Opinion, question, or debate — no clear action, skip
- ❌ **SKIP** — Nitpick marked `nit:`, already addressed, or out of scope

Use this judgment:
- If the reviewer asks "why not X?" with no clear preference → DISCUSSION
- If the reviewer says "rename this to X", "extract this", "this will cause Y bug" → ACTIONABLE
- If comment starts with `nit:` or `optional:` → SKIP (unless --fix-nits flag passed)
- If comment references a line that no longer exists in the diff → SKIP
- If the review body lists Critical/Important issues with specific file references → ACTIONABLE

Print the triage table before making any changes:

```
## PR Comment Triage

| # | Source | File | Author | Status | Action |
|---|--------|------|--------|--------|--------|
| 1 | Review body [C1] | src/app/api/public/... | @alice | ✅ ACTIONABLE | Add rate limiting |
| 2 | Review body [I1] | packages/db/src/... | @alice | ✅ ACTIONABLE | Rename misleading column |
| 3 | Inline | src/foo.ts:42 | @bob | ⚠️ DISCUSSION | Asked about approach |
| 4 | Inline | src/baz.ts:88 | @carol | ❌ SKIP | Nit about formatting |
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
- After fixing, stage and commit but **before pushing**: re-read AGENTS.md/CLAUDE.md and self-review your diff. Check architecture compliance, code standards, naming, no console.logs, no commented-out code. Fix any violations before pushing.
- **Every unaddressed comment MUST get a reply** — for DISCUSSION and SKIP comments, post a reply on the PR thread explaining why it wasn't actioned (e.g., "This is a design choice because...", "Skipping this nit for now — will address in a follow-up", "This line no longer exists after the refactor"). Never leave a reviewer's comment without a response.
- **Resolve threads after fixing** — after fixing a CodeRabbit or GitHub quality check comment, resolve the conversation thread. Use `gh api` to resolve the thread: `gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "ID"}) { thread { isResolved } } }'`. For comments you replied to but didn't fix (DISCUSSION/SKIP), also resolve after posting your rationale reply.
