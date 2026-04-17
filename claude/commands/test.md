---
description: Spawn an agent team to write and run tests for the current branch's changes
allowed-tools: Agent, Bash, Read, Write, Edit, MultiEdit, Grep, Glob, mcp__playwright__browser_navigate, mcp__playwright__browser_snapshot, mcp__playwright__browser_click, mcp__playwright__browser_take_screenshot, mcp__playwright__browser_type, mcp__playwright__browser_select_option, mcp__playwright__browser_wait_for, mcp__playwright__browser_press_key, mcp__playwright__browser_fill_form, mcp__playwright__browser_evaluate, mcp__playwright__browser_network_requests
---

# /test — Agent Team Testing

Spawn an agent team to write tests and verify the current branch's changes via browser and unit tests.

Usage:
- `/test` — auto-detect what changed and test it
- `/test <url-path>` — test a specific page path

Arguments: $ARGUMENTS

## Step 1 — Determine what changed and the dev server port

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
git diff --name-only main-do...HEAD
```

Find the dev server port for this worktree:
```bash
WORKTREE_PATH=$(git rev-parse --show-toplevel)
lsof -i -P -n | grep LISTEN | grep -E "^node|^bun" | while read line; do
  PID=$(echo $line | awk '{print $2}')
  PORT=$(echo $line | grep -oE '[0-9]+$' | head -1)
  CWD=$(lsof -p $PID 2>/dev/null | grep cwd | awk '{print $NF}')
  if [[ "$CWD" == *"$WORKTREE_PATH"* ]] || [[ "$WORKTREE_PATH" == *"$CWD"* ]]; then
    echo "$PORT"
    break
  fi
done
```

Fallback: check `.claude/launch.json` or worktree metadata for port. Last resort: port 3000.

If the diff is small (under 3 files, no UI changes), use a **single agent** instead of a team.

## Step 2 — Spawn the test team

Create an agent team with these teammates. Give each the diff, changed file list, and dev server port.

**Teammates:**

1. **Unit Test Writer** — Write Vitest unit tests for changed logic. Focus on:
   - New/modified functions in services, connectors, queries, utils
   - Edge cases: null inputs, empty arrays, boundary values, error paths
   - Place tests next to source files as `*.test.ts(x)`
   - Use existing test patterns in the codebase as reference
   - Run `bun run test` after writing to verify they pass

2. **Browser Tester** — Run Playwright tests against `http://localhost:{PORT}`. Focus on:
   - Navigate to pages affected by the diff
   - Verify the happy path works (page loads, data renders, interactions work)
   - Check error states and empty states if applicable
   - Take screenshots of key states as evidence
   - Report PASS/FAIL with specific observations

**Instructions for all teammates:**
- Only test code in the **diff**, not the entire app
- Share findings: if the browser tester finds a bug, tell the unit test writer to add a regression test
- If a test fails, investigate whether it's a real bug or a test issue

## Step 3 — Report

After all teammates complete, synthesize:

```
## Test Results: [branch]

### Unit Tests
- [X] new tests written
- [X] existing tests pass
- Files: [list of test files created/modified]

### Browser Tests
| Page | Scenario | Result | Notes |
|------|----------|--------|-------|
| /path | [scenario] | PASS/FAIL | [notes] |

### Screenshots
[list any captured screenshots]

### Verdict: [PASS / FAIL]
[If FAIL: list specific failures and whether they're bugs or test issues]
```

## Step 4 — Fix (if running inside autopilot)

If this is called from `/with-markers` or autopilot context:
1. If browser tests found bugs, fix them
2. If unit tests fail, fix the code (not the tests, unless the test is wrong)
3. Stage new test files and fixes
4. Report what was fixed
