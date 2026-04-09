---
description: Detects the current worktree's dev server port and runs thorough Playwright browser tests for the active branch's changes
allowed-tools: Bash, mcp__playwright__browser_navigate, mcp__playwright__browser_snapshot, mcp__playwright__browser_click, mcp__playwright__browser_take_screenshot, mcp__playwright__browser_type, mcp__playwright__browser_select_option, mcp__playwright__browser_wait_for, mcp__playwright__browser_press_key, mcp__playwright__browser_fill_form, mcp__playwright__browser_evaluate, mcp__playwright__browser_network_requests, Read, Grep, Glob
---

# /test — Worktree Browser Testing

Detect the active dev server port for this git worktree and run thorough Playwright browser tests against it.

Usage:
- `/test` — auto-detect port and test the current branch's changes
- `/test <url-path>` — test a specific path (e.g. `/test /dashboards/ai-analytics`)

**Arguments:** $ARGUMENTS

## Step 1 — Verify we're in a worktree

```bash
git rev-parse --show-toplevel
git worktree list
```

Check if the current directory is a worktree (not the main repo). Note the worktree path.

## Step 2 — Find the correct port

The Next.js dev script hardcodes `-p 3000`, but worktrees start on different ports.

Run this to find which port belongs to this worktree:

```bash
# Find all listening node/bun processes and their ports
lsof -i -P -n | grep LISTEN | grep -E "^node|^bun" | grep -E "[0-9]{4,5}"
```

Then cross-reference with the worktree path by checking which process is serving files from this directory:

```bash
WORKTREE_PATH=$(git rev-parse --show-toplevel)

# Find the PID of the process running from this worktree
lsof -i -P -n | grep LISTEN | while read line; do
  PID=$(echo $line | awk '{print $2}')
  PORT=$(echo $line | grep -oE '[0-9]+$' | head -1)
  CWD=$(lsof -p $PID 2>/dev/null | grep cwd | awk '{print $NF}')
  if [[ "$CWD" == *"$WORKTREE_PATH"* ]] || [[ "$WORKTREE_PATH" == *"$CWD"* ]]; then
    echo "PORT=$PORT PID=$PID CWD=$CWD"
    break
  fi
done
```

If the above doesn't find it, try:
```bash
# Check .claude/launch.json for port hints
cat .claude/launch.json 2>/dev/null | grep -i port
# Or check for port in process list
ps aux | grep "next dev" | grep -v grep
```

Fall back to port 3000 only if no other port is found.

## Step 3 — Determine what to test

Identify what changed in this branch vs main-do:

```bash
git diff main-do...HEAD --name-only
```

Read the key changed files to understand what functionality to test. Focus on user-facing changes.

If `$ARGUMENTS` specifies a URL path, start testing there. Otherwise infer the correct URL from the changed files:
- Files under `@filters/` → `/dashboards/ai-analytics`
- Files under `dashboards/teams/` → `/dashboards/teams`
- etc.

## Step 4 — Run thorough browser tests

Navigate to `http://localhost:{PORT}{path}` and test systematically.

### For each user-facing change, verify:

1. **Happy path** — the feature works as intended
2. **Edge cases** — boundary conditions, empty states, error states
3. **Regression check** — previously working behavior still works
4. **Visual check** — take screenshots of key states

### Testing approach:
- Use `browser_snapshot` to understand page structure before clicking
- Use `browser_take_screenshot` to capture before/after states for key interactions
- Use `browser_click` to interact with UI elements
- Use `browser_navigate` to test different URL param combinations
- Use `browser_evaluate` to inspect DOM/state if needed

### Reporting:

After each test scenario, report:
- ✅ PASS — what was tested, what was observed
- ❌ FAIL — what was tested, what went wrong, screenshot reference

## Step 5 — Final summary

Provide a concise test report:

```
## Test Results — [branch name]
**Port:** [port]
**URL:** [tested URL]

### Scenarios Tested
| Scenario | Result | Notes |
|----------|--------|-------|
| [scenario] | ✅/❌ | [notes] |

### Screenshots
[list any saved screenshots]

### Verdict
[PASS/FAIL with summary]
```

If tests fail, propose specific fixes.
