---
name: browser-verify
description: >
  Visually verify a page in the running dev server using Playwright MCP.
  Use after making UI changes, before pushing code, or when asked to
  "check the page", "verify it works", "take a screenshot", or
  "make sure nothing is broken". Also triggered by /autopilot after
  implementation and before PR creation. Catches full-page regressions,
  not just the changed component.
argument-hint: "[url-path or description of what to verify]"
allowed-tools:
  - Bash
  - Read
  - Grep
  - mcp__playwright__browser_navigate
  - mcp__playwright__browser_snapshot
  - mcp__playwright__browser_click
  - mcp__playwright__browser_take_screenshot
  - mcp__playwright__browser_evaluate
  - mcp__playwright__browser_console_messages
  - mcp__playwright__browser_network_requests
  - mcp__playwright__browser_wait_for
  - mcp__playwright__browser_tabs
  - mcp__playwright__browser_close
---

# Full-Page Browser Verification

Visually verify that a page loads correctly, all sections render, and no regressions
were introduced. This is NOT a unit test runner — it's a visual and functional
smoke check using the live dev server.

## When This Skill Runs

- **Automatically** by `/autopilot` before creating a PR (step 5)
- **Automatically** by `/with-markers` after fixing review comments
- **Manually** via `/browser-verify /dashboards/ai-analytics`
- **By Claude's judgment** when it makes UI changes and wants to verify them

## Step 1 — Resolve the Dev Server URL

Determine the port of the running dev server for this worktree:

```bash
# From environment (set by tmux session)
echo "$SERVER_PORT"
```

If `$SERVER_PORT` is empty, find it:
```bash
# From launch.json
cat .claude/launch.json 2>/dev/null | grep -o '"port": [0-9]*' | head -1 | grep -o '[0-9]*'
```

If still empty, check the server log referenced in `$AUTOPILOT_DIR` or fall back to 3000.

Base URL: `http://localhost:${PORT}`

## Step 2 — Determine What to Verify

**If `$ARGUMENTS` is a URL path** (starts with `/`):
Navigate directly to `${BASE_URL}${ARGUMENTS}`

**If `$ARGUMENTS` is a description** (e.g., "the incidents page"):
Infer the URL from the description and navigate.

**If no arguments** — infer from recent changes:
```bash
git diff main-do...HEAD --name-only 2>/dev/null | head -20
```
Map changed files to their corresponding pages. See [page-mapping.md](page-mapping.md)
if available, otherwise use directory structure conventions.

## Step 3 — Full-Page Health Check

This is the critical step. Do NOT only check the component you changed.

### 3a. Navigate and wait for load
```
browser_navigate → target URL
browser_wait_for → networkidle or specific selector
```

### 3b. Check for errors FIRST
```
browser_console_messages → look for errors, warnings, unhandled rejections
```

**Red flags that MUST be reported:**
- `TypeError`, `ReferenceError`, `SyntaxError` in console
- `500`, `404` in network requests
- `Cannot read properties of undefined/null`
- `column "X" does not exist` (database schema mismatch)
- `Hydration failed` (SSR/client mismatch)
- Any error that mentions a file YOU changed

### 3c. Verify ALL visible sections load

Use `browser_snapshot` to get the page structure. For each major section:

1. **Is it visible?** (not hidden, not display:none)
2. **Does it have content?** (not empty, not showing only a loading spinner)
3. **Does it show real data?** (not "0", "NaN", "undefined", or placeholder text)

If a section shows a loading spinner for more than 10 seconds after page load,
that's a failure — the data fetch is broken.

### 3d. Take screenshots

Capture the full page state:
```
browser_take_screenshot → save to /tmp/verify-{worktree}-{timestamp}.png
```

If the page is long, take multiple screenshots (top, middle, bottom) or
use `browser_evaluate` to scroll and capture.

## Step 4 — Report Results

Structure your findings as:

### All Clear
```
✅ Page verified: /dashboards/ai-analytics
  - All 4 KPI cards rendering with data
  - All 3 charts loaded
  - No console errors
  - Filters responsive
  Screenshot: /tmp/verify-ECH-672-1713200000.png
```

### Issues Found
```
⚠️ Page verified with issues: /dashboards/ai-analytics

REGRESSIONS (caused by your changes):
  ❌ CodeRabbit chart shows "Cannot read properties of undefined"
     → coderabbit-queries.ts line 42 returns null when no data

PRE-EXISTING ISSUES (not caused by your changes):
  ⚠️ Anthropic spend chart shows stale data from March
     → Known issue, not related to this PR

Console errors: 2 (1 new, 1 pre-existing)
Screenshot: /tmp/verify-ECH-672-1713200000.png
```

## Step 5 — Act on Results

- **Regressions caused by your changes** → FIX before pushing. Do not proceed.
- **Pre-existing issues** → Note in PR description under "Known Issues". Do not fix.
- **All clear** → Proceed to push/PR creation.

## Rules

- NEVER skip the console error check. Console errors are the #1 signal of breakage.
- NEVER report "page looks fine" without checking the console.
- NEVER ignore a loading spinner — if it's been >10s, the data fetch is broken.
- If you can't reach the dev server, check the server log for crash/build errors.
- Screenshots are MANDATORY — even if everything passes. They go in the PR description.
- If verifying after fixing review comments, compare to the previous state if possible.
