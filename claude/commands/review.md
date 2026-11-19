---
description: Orchestrates code reviews by dispatching specialized review agents concurrently to analyze code quality, security, performance, and patterns
allowed-tools: Agent, Bash, Read, Grep, Glob, Write
---

# /review — Agent Team Code Review

Spawn an agent team to review changes. Teammates review independently, share findings, challenge each other. **Findings are delivered as inline PR review comments anchored to the exact file:line — never as one wall-of-text comment that quotes file contents** (see Step 3; that format is unusable in the GitHub UI). **Nothing is ever posted to the PR without the user's explicit confirmation** (Step 3b).

Usage:
- `/review` — review current branch vs `main-do`
- `/review <PR-url-or-number>` — review a GitHub PR and post inline comments on it
- `/review --fix` — review with auto-fix enabled

Arguments: $ARGUMENTS

## Step 1 — Determine the target and the diff

**If `$ARGUMENTS` contains a PR URL or number** (e.g. `.../pull/4371` or `#4371`), the target is that PR:

```bash
# owner/repo come from the URL; for a bare number use the current repo's origin.
# The Pilot shell compacts `git`/`gh` diff output — bypass it with `rtk proxy` to get the FULL diff:
rtk proxy gh pr view <num> --repo <owner/repo> --json number,title,baseRefName,headRefName,additions,deletions,changedFiles
rtk proxy gh pr diff <num> --repo <owner/repo> > /tmp/review.diff          # full diff
rtk proxy gh api repos/<owner>/<repo>/pulls/<num>/files --paginate         # path + line counts
rtk proxy gh api repos/<owner>/<repo>/pulls/<num> --jq .head.sha           # head SHA, needed to anchor comments
```

- **Auth/host fallback:** the `github-*` MCP tools hit `api.github.com` and may 404 on enterprise or SSO-gated orgs. The `gh` CLI usually works — for an enterprise host prefix `GH_HOST=<host>` (detect it from the repo's `git remote -v` / `~/.ssh/config`). Verify with `gh auth status`. Use whichever (MCP or `gh`) can actually read the PR.
- Strip generated/noise files from the diff before the agents read it (Drizzle/migration snapshots, `*.lock`, `dist/`, `openapi.json`, generated clients) so they spend tokens on real code.

**Otherwise** the target is the local branch (no PR to comment on):

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
BASE="main-do"
git diff --stat "$BASE"...HEAD
git diff --name-only "$BASE"...HEAD
```

If the diff is empty, inform the user and stop. Count changed files/lines: **< 5 files and < 100 lines → use a single agent** (team overhead not worth it); anything larger → proceed with the team.

## Step 2 — Spawn the review team

Give each teammate the full diff and the changed-file list. Teammates share findings and challenge questionable calls.

**Teammates:**

1. **Bug Hunter** — logic errors, off-by-one, null derefs, race conditions, unhandled error paths, wrong return types. Ignore style. Only runtime-incorrect behavior.
2. **Security Auditor** — injection, auth bypass, exposed secrets, missing boundary validation, unsafe data handling, PII in logs. OWASP top 10 against the diff. Ignore internal-only paths with no external input.
3. **Architecture Reviewer** — conformance to **the target repo's own conventions**. When the repo documents its conventions in an `AGENTS.md` (layering, cache wrappers, result types, import paths), that file is the standard. Otherwise infer the established patterns from the surrounding code in the diff — do **not** impose one repo's rules on a different codebase.

**Instructions for all teammates:**
- Review the **diff only**, not the whole codebase.
- Cite `file:line` using the **real source line number** (map diff hunk offsets back to the file — never cite a line number from your local diff copy).
- Severity: CRITICAL (will break) · IMPORTANT (should fix) · MINOR (nice to have).
- If unsure, say so — no false positives. Verify uncertain claims against the actual file at the PR head before reporting (e.g. confirm an import exists rather than flagging it as "maybe missing").
- **Writing style:** apply `~/.claude/rules/plain-language.md` to every finding body — read it before writing. Short causal sentences; no truth tables or invented shorthand; gloss project-internal terms on first use; leave standard industry vocabulary undefined.

## Step 3 — Deliver findings as INLINE review comments (mandatory format)

**Never post a single summary comment that quotes file contents.** Each finding goes where the code is, anchored to its line in the diff.

### When the target is a PR

Deliver **one review** containing all findings as inline comments. Three sub-steps, in order: build the payload → **confirm with the user** → post.

**3a. Build the payload** — `/tmp/review.json` shape:
```json
{
  "commit_id": "<head SHA from Step 1>",
  "event": "COMMENT",
  "body": "<short verdict + only NON-line-specific notes — no file quotes>",
  "comments": [
    { "path": "<file>", "line": <real source line>, "side": "RIGHT",
      "body": "**[SEVERITY]** self-contained explanation + suggested fix" }
  ]
}
```

**3b. ⛔ Confirmation gate — NEVER post without explicit user approval.** After the payload is built (dedup + plain-language gate already applied), present a compact summary in chat:

- Verdict and review event (`COMMENT` or `REQUEST_CHANGES`), plus finding counts by severity.
- One line per finding: `file:line — [SEVERITY] one-sentence gist` (gist, not the full comment body).
- Anything that will be deleted first (stale comments from a previous run of this review).

Then ask via `AskUserQuestion`: **Post review** / **Revise first** (take the user's feedback, update the payload, re-confirm) / **Don't post** (print the findings in chat instead and stop). Post only on explicit approval. If running unattended (conductor, `/with-markers`, or any context where the user can't respond), do **not** post — print the grouped findings and stop.

**3c. Post** — single API call, only after approval:

```bash
GH_HOST=<host> gh api --method POST repos/<owner>/<repo>/pulls/<num>/reviews --input /tmp/review.json
```

Rules:
- **Anchor only to lines present in the diff** (added/changed/context lines inside a hunk). GitHub rejects comments on unchanged lines outside any hunk — anchor to the nearest in-hunk line and reference the off-hunk line numbers in the comment text.
- `side: "RIGHT"` for added/context lines; `"LEFT"` for removed lines. Use `start_line` + `line` for a multi-line range.
- Each inline `body` is **self-contained**: severity tag, what's wrong, the concrete consequence, the fix. Don't paste the source code back — the comment is already on it.
- The review-level `body` holds **only** the verdict and findings that aren't tied to a specific line (e.g. "verified clean: no SQLi / authz consistent / migration integrity OK", and any whole-PR observation). No quoted file blocks.
- Set `event` to `REQUEST_CHANGES` if there is any CRITICAL finding, else `COMMENT`.
- If you must re-run a review, delete your previous review's stale comment(s) first so the PR doesn't accumulate duplicates.
- Deduplicate across teammates; on a severity disagreement, take the higher.
- **Plain-language gate before posting:** teammate findings are drafts, not final copy. Re-read every comment body (and the review-level body) per `~/.claude/rules/plain-language.md` and rewrite anything non-compliant — never paste teammate prose verbatim into the payload. Same gate applies to the chat-printed findings for local-branch targets.
- After posting, report the review URL to the user — do **not** reprint the full findings in chat.

### When the target is a local branch (no PR)

There's nowhere to post inline. Print the findings in chat as `file:line` anchored bullets grouped by severity, and offer to create/push a PR so they can be posted inline.

## Step 4 — Fix (if `--fix` flag or called from conductor)

If `--fix` is present or running inside `/with-markers`:
1. Apply fixes for all CRITICAL and IMPORTANT findings.
2. Run `bun run typecheck` and `bun run lint`; fix anything new they surface.
3. Report what was fixed.

Otherwise it's a dry review — post the inline review (PR target) or print the grouped findings (local target), and stop.
