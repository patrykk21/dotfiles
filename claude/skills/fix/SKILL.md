---
name: fix
description: "Bugfix workflow — investigate, RED test, fix, verify end-to-end, done. Standard command for bugs. Stops cleanly and asks the user to re-invoke with /spec when the bug exceeds this workflow's scope."
argument-hint: "<bug description>"
user-invocable: true
model: opus[1m]
---

# /fix — Bugfix Workflow

Bugfix workflow with TDD. Investigate the bug, write the failing test, fix at the root cause, verify the fix end-to-end, done. No plan file, no approval gate mid-flow, no separate verify phase.

```bash
> /fix "annotation persistence drops fields between save and reload"
> /fix "off-by-one in pagination at boundary"
> /fix "wrong default for max_retries"
```

**Always quick.** If investigation reveals the bug is multi-component, architectural, or otherwise larger than a quick fix, STOP cleanly and tell the user to re-invoke with `/spec`. Do NOT silently switch lanes — `/fix` means quick, `/spec` means the full workflow. Honour the user's command choice.

---

## Iron Laws

```
1. NO FIXES WITHOUT ROOT CAUSE — traced to file:line, explained WHY.
2. NO CODE WITHOUT A FAILING REPRODUCING TEST — TDD.
3. FIX AT THE SOURCE — not where the error appears.
4. END-TO-END VERIFICATION IS MANDATORY — Step 4 runs the actual program (UI: Claude Code Chrome / Chrome DevTools MCP / playwright-cli / agent-browser; CLI/API/library: real invocation) and captures concrete evidence. Unit tests alone are never accepted as proof.
5. STOP WHEN OVER YOUR HEAD — multi-component / architectural bugs need /spec.
```

### Common rationalizations

| Excuse | Reality |
|--------|---------|
| "Emergency, no time for process" | Systematic is faster than guess-and-check thrashing. |
| "Issue is simple, don't need to trace" | Simple bugs have root causes too — tracing one file is fast. |
| "I'll write the test after confirming the fix" | Tests written after pass immediately and prove nothing. RED first or it isn't TDD. |
| "One more fix attempt" (after 2 failures) | Two failed quick-lane attempts means the lane is wrong. Bail to /spec. |
| "Looks fixed, tests pass" | E2E evidence required. Unit-pass is not user-pass. |
| "Quick patch now, investigate later" | This IS the quick lane. If you can't trace it now, bail to /spec — don't patch blind. |

---

## Critical Constraints

- **No plan file.** All state lives in this conversation. If compaction happens mid-fix, re-read the conversation summary and resume.
- **No `Iterations:` counter.** If your fix doesn't work after one re-attempt, stop and tell the user to switch to `/spec` — don't loop.
- **No approval mid-flow.** Single end-of-flow confirmation only when `PILOT_PLAN_APPROVAL_ENABLED` is enabled.
- **Stopping is success, not failure.** Recognising "this is bigger than a quick fix" and bailing out is the right call. Wasting time in the quick lane on a multi-component bug is the failure.

---

## Bail-Out Triggers — Stop and Tell the User to Use `/spec`

You MUST stop and tell the user to re-invoke with `/spec` when ANY of these is true after Step 1 investigation:

- **Confidence is Low** — you can't pin root cause to `file:line` after Step 1.
- Two quick-lane fix attempts have already failed.
- The fix has **non-trivial UI implications** that warrant a recorded Verification Scenario (multi-step user flow, regression-prone interaction, visual states the user would want recorded).
- Fix introduces **new abstractions** — a new module, a new public API, a new data structure, a new workflow phase, or a new file that wasn't previously part of the surface area.
- Fix requires **architectural redesign** — the existing pattern itself must change (e.g., swapping the storage layer, restructuring a state machine, replacing a contract). Adding a missing guard or a missing field along an existing pattern is **not** a redesign.
- Net new production code is likely to exceed **~150 lines** (rough ceiling — if you can't size it yet, sketch the diff first).
- The change crosses **independent components with unrelated logic** — e.g., a frontend bug AND an unrelated backend bug bundled together. Coordinated changes that apply the **same conceptual fix** at multiple guard sites do NOT trigger this — that's a single logical bug, multiple sites. Example of allowed: adding the same iteration cap to both a feature-verify orchestrator and a stop-guard hook because they are two layers of the same missing-budget defect.

**Defense-in-depth nuance.** When the bug *is* "a guard is missing across N existing sites", fixing all N sites in one shot is the correct quick-lane move. That is not "defense-in-depth at multiple layers" in the bail-out sense — it's "one fix, applied consistently." Bail only when each layer needs **different** logic (entry validation + business rule + storage migration, each non-trivial).

**Multi-file is fine** when files share the same pattern. The trigger is **abstraction count and logic divergence**, not file count.

**How to bail out** — do all four:

1. Summarise what you found (root cause hypothesis, files involved, why it exceeds quick-lane scope).
2. Tell the user explicitly: "This bug needs the full workflow. Please re-invoke with `/spec '<bug description>'`."
3. Do NOT invoke `spec-bugfix-plan` yourself. Honour the command boundary — the user chose `/fix`.
4. Stop.

---

## Workflow — Six Steps, No Ceremony

See `steps/01-investigate.md` through `steps/06-finalise.md`.

## Step 1: Investigate Root Cause

**Goal:** trace the bug to `file:lineN — function() does X but should do Y` with High or Medium confidence. If you can't, bail out (see orchestrator).

### 1.1 Reproduce & understand

- Restate **symptom**, **trigger**, **expected behaviour**.
- If too vague: one focused `AskUserQuestion` (only when `PILOT_PLAN_QUESTIONS_ENABLED` is not `"false"`).
- If you can't trigger it after 2 attempts: bail out. Tell the user the bug isn't reproducible from the description alone, ask them to either provide more detail or re-invoke with `/spec` for the full investigation workflow. The quick lane is for reproducible bugs.

### 1.2 Recent changes (one bash call, then move on)

```bash
git log --oneline -10 -- <suspected_file_or_dir> 2>/dev/null
```

Look for the commit that introduced the bug. If recent, read that diff. If nothing obvious, skip.

**Bisect when `git log` doesn't reveal it.** If the bug appeared between two known-good and known-bad states and the suspect commit isn't obvious, run `git bisect start <bad> <good>` then `git bisect run <test-cmd>` against the reproducing test you'll write in Step 2 — this pinpoints the introducing commit automatically. Skip when the surface area is small enough that a single read finds it.

### 1.3 Trace to root cause

**Start with `codegraph_context(task="<bug description>")`** — single call, returns entry points and related symbols. Read it carefully.

For local bugs (single file, single function): one or two targeted `Read`s on the file from the codegraph output is enough. **Do not** run `codegraph_callers`/`callees`/`impact` for local bugs — that's the full-lane bias and it's the single biggest time sink for trivial fixes.

For bugs that span 2 files in the same component (e.g. service.ts + service.test.ts): targeted `Read`s. Still no full call-graph traversal.

**Bail-out check at end of 1.3:** if you can't pin file:line, or each touched file would need **different** logic (not the same pattern repeated) — stop and tell the user to use `/spec` (see orchestrator's bail-out triggers for the full list). Multi-file traces are fine when each site needs the *same* fix; that's one logical bug, multiple guard sites. Don't switch lanes silently.

### 1.4 Instrument when needed (UI / async / race / timing bugs)

For bugs that don't surface clearly through stack traces or static reading — UI rendering glitches, async timing, race conditions, integration-layer issues — add **temporary diagnostic logging** to the production code and trigger the bug to read the output:

- Log input values entering the suspect function.
- Log branch conditions (which path executed?).
- Log computed intermediate results.
- Log return values at layer boundaries.

**Mark every temporary log with `SPEC-DEBUG:`** (e.g. `console.log("SPEC-DEBUG: filters=", filters)`). Step 3.5 greps for this marker — any unremoved match fails the diff sanity check.

**Unknown caller?** If the bug is in shared code reached from many sites and you don't know which caller triggers it, capture the call chain inline:

```js
// SPEC-DEBUG: who is calling this with bad input?
console.error("SPEC-DEBUG:", { args, stack: new Error().stack });
```

Run, read the stack, identify the offending caller, then trace upward to the original trigger.

**Performance regressions are different.** Value-logging is the wrong tool — replace it with baseline measurement: timing harness, `performance.now()`, profiler, or query plan / `EXPLAIN`. Establish current vs expected timing first, then bisect against that signal (Step 1.2). Measure first, fix second.

Skip 1.4 when the stack trace already names the failing line, or when a static read of the file is enough to see the bug. Skip is the default.

### 1.5 State the root cause

Out loud, in one sentence to the user, before writing any test:

> "Root cause: `<file>:<line>` — `<function>()` does <X>, should do <Y>. This causes the symptom because <reason>. Confidence: <High|Medium>."

If confidence is Low: bail out. Don't guess in the quick lane.

### 1.6 Lock in a fast signal before Step 2

Your reproducing signal — what runs in <30s and definitively shows fail/pass — must be **fast and deterministic** before you write the fix. For most bugs that's the unit test you're about to write in Step 2. For UI / integration / async bugs the unit-test seam may be wrong, and your real signal is a `curl`, CLI invocation, or headless-browser command (the same one you'll run in Step 4 E2E).

Whichever it is, sharpen it now:

- **Slow loop (>30s)?** Narrow the test scope, skip unrelated setup, cache fixtures. A flaky 30s loop is the slowest path to a fix.
- **Flaky?** Pin time, seed RNG, isolate filesystem, freeze network. For non-deterministic bugs, raise the reproduction rate (loop the trigger 50–100×, parallelise) until it's debuggable — a 1% flake is not.
- **Wrong symptom?** The signal must fail with the **user's** reported symptom, not a different failure that happens to be nearby. Wrong bug = wrong fix.

If you cannot get a fast deterministic signal after one pass of sharpening, that's a bail-out trigger — tell the user to use `/spec`. Don't hypothesise into a flaky loop.

### Red flags — STOP and re-investigate

- "Quick fix for now, investigate later" → STOP, this IS the quick lane.
- "I'll just try changing X" → STOP, trace it first.
- "It's probably X" → STOP, prove it.
- "I see the symptom, let me fix it" → seeing symptoms ≠ understanding root cause.

If the user says "stop guessing", "is that not happening?", "ultrathink this" — STOP, return to 1.3.

## Step 2: Write the Reproducing Test (RED)

**No production code yet.** A bugfix without a failing test is a rubber-stamp fix. The quick lane keeps this step minimal — but it does not skip it.

### 2.1 Pick the entry point

Use an **existing public entry point** the bug is reachable through (function, endpoint, CLI command). Don't write a test that calls a helper you're about to create — those tests can't fail before the fix.

If no clean entry point exists: that's a design smell. Document it briefly and use the closest stable one. Don't refactor "to make it testable" in the quick lane — bail out (tell the user to re-invoke with `/spec`) if the smell is large.

**Modify, don't duplicate.** If a test class already covers this entry point (e.g. you can `grep` for the function name in `tests/` and find one), add the new failing test as a method INSIDE that class. Do NOT create a new test class just because the bug is "different". Prefer one class per production class/public entry point, not one class per symptom.

### 2.2 Encode `Currently → Expected`

The test asserts the **correct** behaviour. Against the buggy code, the assertion must fail with an error matching the symptom you stated in Step 1.4.

Naming: `test_<function>_<bug>_<expected>` (Python) or `it("should <expected> when <condition>", ...)` (TS/JS). Keep it boring — this is regression insurance, not a showcase.

### 2.3 Run it — it MUST fail

```bash
<test command for ONLY this test, e.g. uv run pytest path/to/test.py::test_name -q>
```

**Outcome interpretation:**

- **Fails with the expected error** → RED proven, proceed to Step 3.
- **Passes** → the test does not encode the bug, OR the bug is already fixed. STOP. Re-read Step 1.5 — did you trace the actual root cause? Re-investigate. Do NOT write fix code.
- **Errors for an unrelated reason** (import error, missing fixture) → fix the test setup first, re-run. Don't proceed until RED is genuine.

### 2.4 No commit yet

Worktree mode: do not commit the test alone. The quick lane bundles test + fix into one commit at finalise. (Full lane uses separate commits because the cp+trap RED proof in verify needs them — quick lane skips that proof, so commit-bundling is fine.)

## Step 3: Fix at the Root Cause

### 3.1 Make the minimal change

Edit only the file(s) at the root cause. One logical fix. No "while I'm here" cleanups, no bundled refactoring, no formatting passes. **Lineage rule:** every changed line traces directly to the bug.

**Multi-site is allowed when each site gets the same conceptual fix** (e.g., adding the same iteration cap to two parallel guard layers because the missing-budget defect lives at both). The constraint is *one logical change, repeated where the same pattern lives* — not "while I'm here, also tweak X."

### 3.2 Forbidden patterns — fix at source, not symptom

If the buggy data flows from upstream, fix upstream. Red flags in the diff:

- Broad new `try/except` around the failing call.
- `if value is None: return default` at the caller when the bug is that `value` is wrong upstream.
- Swallowed exceptions, silently normalised bad inputs.
- Early return that hides wrong state from the caller.
- Renamed/suppressed log lines that previously surfaced the bug.

**Quick-lane fixes are single-pattern.** If each candidate fix site needs **different** logic (entry validation + a business rule + a storage migration, each non-trivial), you're in `/spec` territory — bail out. Adding the *same* guard at multiple parallel sites is fine; that's still one logical change. The trigger is *logic divergence*, not site count.

### 3.3 Run the reproducing test — it MUST pass

```bash
<same single-test command from Step 2.3>
```

If it doesn't pass: stop adding more code. Revert your edit. Return to Step 1.3 — your root cause hypothesis was wrong.

### 3.4 Run the targeted scope (NOT full suite)

Run the test module(s) covering the file you just changed. Fast, scoped:

```bash
# Python example
uv run pytest <path/to/test_module.py> -q
# TypeScript example
bun test <path/to/test-file.test.ts>
```

Zero failures. The full anti-regression suite runs once at Step 5 — running it after every fix iteration is the quick-lane anti-pattern.

### 3.5 Diff sanity

```bash
git diff --name-only
git diff | grep -E "^\+.*\b(try:|except|catch \(|return None|return \[\]|return \{\}|console\.log|print\()"
```

- **Root-cause file IS in the diff.** If not, the fix is at a symptom — return to 3.1.
- **No unplanned files appear.** If they do, revert them now.
- **Diff is small** — usually < 20 lines for single-site fixes, < ~150 net new production lines for multi-site pattern fixes. If it ballooned past that ceiling, the bug exceeds the quick lane — bail out.
- **Every grep match must be justified or reverted.** Look for symptom-patching, swallowed returns, or leftover `print` / `console.log` / `SPEC-DEBUG:` markers.

### 3.6 If your first fix doesn't work — one re-attempt, then bail out

If Step 3.3 fails: revert, re-investigate, try once more.

If the second attempt also fails: **stop and tell the user to re-invoke with `/spec`**. Two failed quick-lane attempts means the bug is deeper than the lane is built for.

## Step 4: Verify End-to-End

⛔ **The primary proof that the bug is fixed.** Run the actual program with the original input and observe the symptom is gone. A passing unit test alone is never accepted.

This is the most important step in the workflow. Skip is NOT an option — no exceptions for "small fix", "obvious fix", "test covers it", "I'm confident".

### Pick the lane that matches the bug

| Bug surface | Tool | Evidence to capture |
|-------------|------|---------------------|
| **UI / web frontend** | 4-tier resolution from `browser-automation.md`: **Claude Code Chrome** → **Chrome DevTools MCP** → **playwright-cli** → **agent-browser**. Walk the user's repro steps. | Page state and element values that prove the correct behaviour |
| **CLI** | The exact command the user ran, with original args + env | Stdout/stderr lines + exit code |
| **HTTP API** | `curl` / HTTP client with the user's body and headers | Status code + the response field that proves the fix |
| **Library / SDK / function** | `python -c '…'`, `node -e '…'`, REPL, or scratch script with the user's args | Returned value |
| **Background job / cron / worker** | Trigger the job manually with the failing input | Relevant log lines |

### Proof requirement

Concrete evidence is mandatory in the Step 6 report. Bare assertions are insufficient:

- ❌ "Looks fixed", "behaves correctly", "tests pass"
- ✅ `curl /search -d '{}' → 200, response.results.length=42`
- ✅ "Saved end_date 2026-05-15, list shows 2026-05-15 (read_page after save confirms)"

### When the symptom persists

The unit test is at the wrong layer — it sits below the user's interaction point. Move the assertion up to the user's actual entry point (API, browser, CLI), then re-run **Step 2.3 (RED) → Step 3.3 (test passes) → Step 4 (E2E re-check)**.

### When the running program is unavailable

Build broken, infra missing, integration env down? Stop and tell the user. Do not finalise the fix without E2E verification — that is the failure mode this step prevents.

## Step 5: Quality Gate

Automated checks — the last green-bar gate before finalise.

### 5.1 Lint + types + build

```bash
# Python project example
ruff check . --fix && ruff format . && basedpyright <src> 2>&1 | tail -5
# TypeScript project example
bun run typecheck && bun run lint
```

Build only when the project has a build step that could surface fix-related errors (TS compile, native compile). Skip for plain Python or pure JS.

### 5.2 Full anti-regression suite

```bash
# Python
uv run pytest -q
# TypeScript
bun test
```

Zero failures. If anything broke that's not in the immediate neighbourhood of your fix:

- **Localised to the same module:** fix it inline, re-run.
- **Far from your fix:** the fix has unintended cross-coupling. **Stop and tell the user to re-invoke with `/spec`** — the bug is bigger than you thought.

### 5.3 Auto-fix re-run

If lint/format/types auto-modified files in 5.1, re-run the suite to confirm those auto-fixes didn't break anything. (This is the only reason 5.2 might run twice.)

## Step 6: Finalise

### 6.1 Worktree mode — single commit

If a worktree was created: bundle test + fix into one commit.

```bash
git add <test_file> <fix_file>
git commit -m "fix: <one-line description>"
```

The conventional `fix:` prefix triggers a patch release if/when this branch ships. Do not split into multiple commits in the quick lane.

### 6.2 Approval gate (only when enabled)

⛔ **Before showing the approval question, you MUST have completed Step 4 (Verify End-to-End) with evidence.** "Tests pass" is not enough — the approval summary must include what you actually ran and what you observed. If you cannot fill in `**E2E:**` below with concrete evidence, you have not finished Step 4 — go back, do not ask for approval.

Read `PILOT_PLAN_APPROVAL_ENABLED`. If `"false"` → skip 6.2 entirely, mark done.

Read `PILOT_CODEX_CHANGES_REVIEW_ENABLED` to decide whether to offer the optional Codex review:

```bash
echo "CODEX_REVIEW=$PILOT_CODEX_CHANGES_REVIEW_ENABLED"
```

When approval is enabled, summarise + ask. Build the `options` array in this order:

1. `"Approve — done"`
2. `"Request changes"`
3. `"Explain the fix in more detail"` — always present.
4. `"Run Codex adversarial review for added confidence"` — **only when** `PILOT_CODEX_CHANGES_REVIEW_ENABLED == "true"`. Omit the entry entirely otherwise; do NOT show a disabled / greyed option.

```
AskUserQuestion(
  question="Bugfix complete.\n\nBug: <one line>\nRoot cause: <file>:<line> — <what>\nFix: <one-line description of the change>\nTests: reproducing test added (<test_name>), full suite green.\nE2E: <command/URL you ran and the concrete observation that proves the fix — e.g. 'curl /search -d {} → 200 with [results]', 'opened /tasks page, saved end_date=2026-05-15, list shows 2026-05-15', 'ran pilot register-plan ./foo.md PENDING → exit 0, plan visible in console'>\n\nReview the diff in the Console's Changes tab. Approve when ready.",
  options=[<see list above>]
)
```

Handle:

- **Approve** → done.
- **Request changes** → user describes problem in free-form. Treat as a new investigation: re-run Step 1.3 (re-trace) → Step 2 onward.
- **Explain the fix in more detail** → write a fuller walkthrough (causal chain from trigger → root cause; why the boundary you fixed at is correct; line-by-line meaning of the diff; alternatives considered and rejected). Do NOT modify code. Then re-ask 6.2 — drop the "Explain" option from the new list to avoid loops; keep the Codex option if still applicable.
- **Run Codex adversarial review** (only present when enabled) → run sub-step 6.2.a, then re-ask 6.2 with this option removed (one Codex run per `/fix` invocation).

#### 6.2.a Optional Codex Adversarial Review

Run **only** when the user explicitly picked "Run Codex adversarial review" in 6.2. Opt-in, never automatic — the quick-lane reproducing test plus Step 4 E2E remain the proof of correctness. Codex is for added confidence on user request.

1. **Locate the companion.** If missing, tell the user "Codex companion not found — install the openai-codex plugin or disable Codex in Console Settings" and return to 6.2 with the Codex option removed.

   ```bash
   CODEX_COMPANION=$(ls ~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs 2>/dev/null | sort -V | tail -1)
   PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-$(pwd)}"
   [ -z "$CODEX_COMPANION" ] && echo "MISSING"
   ```

2. **Build the review prompt file** by rendering the **template at `${CLAUDE_PLUGIN_ROOT}/agents/changes-review-codex.md`** (the same template `spec-verify` uses — single source of truth for code-review semantics).

   For `/fix`, the "plan" is the conversation, not a file. Inline a one-page plan into a temp file so the template's `{{PLAN_PATH}}` substitution has something to point at:

   ```bash
   PROMPT_TEMPLATE="${CLAUDE_PLUGIN_ROOT}/agents/changes-review-codex.md"
   PROMPT_FILE="/tmp/codex-fix-review-${PILOT_SESSION_ID:-default}-$$.md"
   FIX_PLAN_FILE="/tmp/codex-fix-plan-${PILOT_SESSION_ID:-default}-$$.md"
   cat > "$FIX_PLAN_FILE" <<'PLAN_EOF'
   # /fix Bugfix Summary
   Bug: <one-line bug>
   Root cause: <file>:<line> — <what>
   Fix: <one-line fix description>
   Reproducing test: <test file>::<test name> (added in Step 3.3)
   PLAN_EOF

   PLAN_GOAL="Bugfix for: <one-line bug>. Root cause at <file>:<line>. The reproducing test must reliably fail before the fix and pass after."
   BASE_REF="$(git rev-parse --abbrev-ref HEAD@{upstream} 2>/dev/null | sed 's|^[^/]*/||' || echo main)"
   CHANGED_FILES=$(git status --short --untracked-files=all | awk '{print "- " $2}')

   PLAN_PATH="$FIX_PLAN_FILE" PLAN_GOAL="$PLAN_GOAL" BASE_REF="$BASE_REF" CHANGED_FILES="$CHANGED_FILES" \
   PROMPT_TEMPLATE="$PROMPT_TEMPLATE" PROMPT_FILE="$PROMPT_FILE" \
   uv run --no-project python -c '
   import os, pathlib
   text = pathlib.Path(os.environ["PROMPT_TEMPLATE"]).read_text()
   for key in ("PLAN_PATH", "PLAN_GOAL", "BASE_REF", "CHANGED_FILES"):
       text = text.replace("{{" + key + "}}", os.environ[key])
   pathlib.Path(os.environ["PROMPT_FILE"]).write_text(text)
   '
   ```

3. **Launch the task in background.** Use `task --background --prompt-file` (the companion's own background mode is supported for `task` — unlike `review`/`adversarial-review`).

   ```
   Bash(
     command="cd $PROJECT_ROOT && node $CODEX_COMPANION task --background --prompt-file \"$PROMPT_FILE\"",
     run_in_background=false,
     timeout=60000
   )
   ```

   Capture the job ID from stdout (`task-…` token). Then poll for completion:

   ```bash
   JOB_ID="<captured-task-id>"
   for i in $(seq 1 150); do
     STATE=$(node "$CODEX_COMPANION" status "$JOB_ID" --json 2>/dev/null \
       | uv run --no-project python -c "import json,sys; print((json.load(sys.stdin).get('job') or {}).get('status') or '')")
     case "$STATE" in
       completed) echo "READY"; break ;;
       failed)    echo "FAILED"; break ;;
     esac
     sleep 4
   done
   ```

   Run this as `Bash(run_in_background=true, timeout=600000)`. ⛔ **Wait for the completion notification** — do NOT read the result file before the `<task-notification>` with `<status>completed</status>` arrives.

4. **On completion notification, retrieve findings via the companion's public interface:**

   ```bash
   node "$CODEX_COMPANION" result "$JOB_ID" --json > /tmp/codex-fix-result-$$.json
   ```

   Read `/tmp/codex-fix-result-$$.json` via `ctx_execute_file`. Verify `storedJob.status === "completed"`, then parse `storedJob.result.rawOutput` as JSON (`{verdict, summary, findings, next_steps}`). If JSON parse fails, fall back to `storedJob.rendered` and surface as a suggestion-level finding.

5. **Act on findings — same severity → action map as `/spec-verify`:**

   | Severity | Action |
   |----------|--------|
   | `critical` / `high` | **must_fix** — fix immediately, re-run the targeted test from Step 3.4 + the full suite from Step 5.2, then re-ask 6.2 |
   | `medium` / `low` | **should_fix** — fix if it's a single-site change consistent with the original bug's lineage; if it would expand scope (3+ files, architectural), summarise to the user and let them decide whether to fix here or open a `/spec` follow-up |
   | `info` | **suggestion** — mention in one line; do not auto-apply |

   If verdict is `approve` and there are no must/should findings: report "Codex: approve — no blocking findings" and re-ask 6.2.

6. **Cleanup.** Delete the temp prompt and bugfix-summary files:
   ```bash
   rm -f "$PROMPT_FILE" "$FIX_PLAN_FILE"
   ```

7. **Launch failure handling.** If `$JOB_ID` is empty after the completion notification, or `storedJob.status` is `"failed"`: surface the captured stderr to the user, do **not** silently mark the bugfix done. Return to 6.2 with the Codex option removed.

### 6.3 Console notification (always, when binary present)

```bash
~/.pilot/bin/pilot notify plan_approval "Bugfix complete" "<one-line bug>" 2>/dev/null || true
```

Best-effort — don't block on failure.

### 6.4 Pre-report verification checklist

⛔ Walk every box before writing the report. Missing any one = not done — return to the relevant step.

- [ ] Reproducing test passes (Step 3.3 fresh run, this message).
- [ ] Full anti-regression suite green (Step 5.2 fresh run).
- [ ] E2E executed against the actual program with concrete evidence captured (Step 4).
- [ ] `git diff | grep -E "SPEC-DEBUG|^\\+.*\\b(console\\.log|print\\()"` returns nothing (no leftover instrumentation).
- [ ] Diff is small and every changed line traces to the bug (lineage rule).
- [ ] Worktree mode: single bundled `fix:` commit. Non-worktree: changes ready, no commit yet.

If any box is unchecked, do not write the report and do not ask for approval — fix the gap first.

### 6.5 Report

```
Bugfix complete — <bug>.
Root cause: <file>:<line>.
Tests: 1 new reproducing test, full suite green.
E2E: <command/URL run> → <observation that proves the symptom is gone>.

Run /clear before starting new work — this resets context while keeping project rules loaded.
```

The `E2E:` line is **mandatory** — it documents that the actual program was exercised, not just the unit tests.

### 6.6 Post-mortem flag (optional, one line)

Ask once, now that you have more information than when you started: **what would have prevented this bug?** If the answer is architectural — no clean test seam, hidden coupling between modules, validation absent at the boundary the bad data crossed, repeated near-miss in the same area — name it as a `/spec` follow-up candidate in one line:

```
Follow-up (architectural): <one-line description> — candidate for /spec.
```

Skip when the answer is "nothing structural, it was a one-line typo / off-by-one / wrong default." Don't manufacture follow-ups.

ARGUMENTS: $ARGUMENTS