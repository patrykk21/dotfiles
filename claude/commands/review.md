---
description: Orchestrates code reviews by dispatching specialized review agents concurrently to analyze code quality, security, performance, and patterns
allowed-tools: Agent, Bash, Read, Grep, Glob, Write
---

# /review — Agent Team Code Review

Spawn an agent team to review the current branch's changes. Teammates review independently, share findings, challenge each other, and produce a single consolidated report.

Usage:
- `/review` - Review current branch vs main-do
- `/review --fix` - Review with auto-fix enabled

Arguments: $ARGUMENTS

## Step 1 — Determine the diff

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
BASE="main-do"
git diff --stat "$BASE"...HEAD
git diff --name-only "$BASE"...HEAD
```

If the diff is empty, inform the user and stop.

Count the changed files and lines. If fewer than 5 files and under 100 lines changed, use a **single agent** instead of a team (overhead not worth it for small changes). For anything larger, proceed with the team.

## Step 2 — Spawn the review team

Create an agent team with these teammates. Give each teammate the full diff context and the list of changed files. Teammates should share findings with each other and challenge questionable calls.

**Teammates:**

1. **Bug Hunter** — Find actual bugs: logic errors, off-by-one, null dereferences, race conditions, unhandled error paths, wrong return types. Ignore style. Only report issues that would cause incorrect behavior at runtime.

2. **Security Auditor** — Find security issues: injection vectors, auth bypasses, exposed secrets, missing input validation at system boundaries, unsafe data handling. Check OWASP top 10 against the diff. Ignore internal-only code paths with no user input.

3. **Architecture Reviewer** — Check against AGENTS.md patterns: layered architecture (services -> connectors -> queries), correct caching wrappers, proper error handling with ServerActionResult, no AbortSignal usage, correct import paths. Flag violations of the project's established patterns.

**Instructions for all teammates:**
- Only review the **diff**, not the entire codebase
- Be specific: cite file:line, quote the problematic code, explain the bug
- Severity levels: CRITICAL (will break), IMPORTANT (should fix), MINOR (nice to have)
- If you're unsure, say so — don't pad findings with false positives
- Share findings with teammates so they can validate or challenge

## Step 3 — Synthesize

After all teammates report, synthesize findings into a single report:

```
## Review: [branch] vs [base]

### Critical (must fix before merge)
- [file:line] — [description]

### Important (should fix)
- [file:line] — [description]

### Minor (consider fixing)
- [file:line] — [description]

### Verdict: [PASS / PASS WITH FIXES / FAIL]
```

Deduplicate findings reported by multiple teammates. If teammates disagree on severity, use the higher one.

## Step 4 — Fix (if --fix flag or called from autopilot)

If `--fix` is present or this is running inside `/with-markers`:
1. Apply fixes for all CRITICAL and IMPORTANT findings
2. Run `bun run typecheck` and `bun run lint` after fixes
3. Fix any new errors introduced
4. Report what was fixed

If this is a dry review (no --fix), just display the report.
