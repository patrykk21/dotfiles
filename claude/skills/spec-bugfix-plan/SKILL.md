---
name: spec-bugfix-plan
description: "Bugfix spec planning phase - investigate root cause, design fix, get approval"
argument-hint: "<bug description> or <path/to/plan.md>"
user-invocable: false
model: opus[1m]
hooks:
  Stop:
    - command: uv run --no-project python "${CLAUDE_PLUGIN_ROOT}/hooks/spec_plan_validator.py"
---

# /spec-bugfix-plan - Bugfix Planning Phase

**Phase 1 (bugfix).** Investigates root cause, creates lean fix plan, gets approval.

**Input:** Bug description (new) or plan path (continue unapproved)
**Output:** Approved bugfix plan at `docs/plans/YYYY-MM-DD-<slug>.md` with `Type: Bugfix`
**Next:** On approval → `Skill(skill='spec-implement', args='<plan-path>')`

**Note:** This skill is invoked when the user types `/spec "<bug description>"` — they chose the full spec workflow. For a bugfix workflow without a plan file, users invoke `/fix` directly (separate user-facing command). The two are distinct entry points — honour the user's choice.

---

## Resuming an Unapproved Plan

When the argument ends with `.md`: read the plan, check `Status:` and `Approved:`. Resume from wherever planning left off:

- No investigation yet → Step 2 (Investigation)
- Has investigation, no tasks → Step 3 (Plan the Fix)
- Complete but unapproved → Step 6 (Approval)

---

## Iron Laws

```
1. NO FIXES WITHOUT ROOT CAUSE — traced to file:line, explained WHY.
2. NO CODE WITHOUT A FAILING REPRODUCING TEST — the RED must exist first.
3. FIX AT THE SOURCE — not where the error appears.
4. ONE UNIFORM STRUCTURE — every bugfix plan has the same three tasks.
```

If Step 2 is incomplete, you cannot propose fixes. Symptom fixes are failure. Retroactive tests are failure. "I know the fix, I'll skip the test" is failure.

---

## Critical Constraints

- **NEVER write code during planning** — planning and implementation are separate phases
- **NEVER assume — verify by reading files.** Trace the bug to actual file:line.
- **Lean ≠ skipping steps.** Small bugs get short tasks, not fewer tasks. The three-task structure (Reproducing Test → Fix → Quality Gate) is non-negotiable.
- **Plan file is source of truth** — survives across auto-compaction cycles
- **ALWAYS use `AskUserQuestion` tool** for clarifications — never list numbered questions in plain text
- **⛔ If `PILOT_PLAN_QUESTIONS_ENABLED` is `"false"` (from Step 0),** skip all `AskUserQuestion` calls (Steps 2.1, 2.5 escalation, 3 approach selection). Make reasonable default assumptions (including selecting the recommended fix approach) and document them in the plan. Continue autonomously.

> **NOTE: During `/spec`, use the structured workflow below — not CC's native plan mode.**

## Step 0: Setup & Red Flags

### 0.1 Read Toggle Configuration

**⛔ Run FIRST, before any other step.** Read all toggle env vars in a single Bash call:

```bash
echo "QUESTIONS=$PILOT_PLAN_QUESTIONS_ENABLED APPROVAL=$PILOT_PLAN_APPROVAL_ENABLED"
```

Reference these values throughout: Steps 2.1/2.5 (questions) and 6 (approval). Bugfix planning does not run Codex — adversarial review only runs once per `/spec` invocation, on the implementation in `spec-verify`.

### 0.2 Red Flags — STOP and Follow Process

**This is a gate, not a reminder.** If any red flag below applies, you are NOT allowed to proceed to Step 3 until Step 2 is fully complete with root cause traced to file:line.

#### Internal red flags (your own thoughts)

- "Quick fix for now, investigate later"
- "Just try changing X and see if it works"
- "It's probably X, let me fix that"
- "I don't fully understand but this might work"
- "I know this codebase, I don't need to trace it"
- "The fix is obvious, let me skip the test"
- Proposing solutions before tracing data flow
- "One more fix attempt" (when already tried 2+)
- Each fix reveals a new problem in a different place

#### Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Issue is simple, don't need process" | Simple bugs have root causes too. The process is fast for simple bugs. |
| "Just try this first, then investigate" | First fix sets the pattern. Do it right from the start. |
| "I'll write the test after confirming the fix works" | Untested fixes don't stick. Test first proves the bug exists. |
| "I see the problem, let me fix it" | Seeing symptoms ≠ understanding root cause. |
| "One more fix attempt" (after 2+ failures) | 3+ failures = architectural problem. Question the pattern, don't fix again. |

#### User signals you're off track

If the user says any of these, STOP and return to investigation — you assumed without verifying:

- "Stop guessing"
- "Is that not happening?" / "Will it show us…?"
- "Ultrathink this"
- "We're stuck?" (frustrated tone)
- Any redirect implying "you should have checked first"

#### Enforcement

Before writing any task in Step 3, you must answer YES to all of these:

1. Can I state the root cause as `file/path:lineN — function_name() does X but should do Y`?
2. Can I explain WHY this causes the symptom (not just what is wrong)?
3. Is my confidence High or Medium (not Low)?

If any answer is NO → return to Step 2. No exceptions, even for "obvious" bugs. Call-graph traversal (`codegraph_callers`/`codegraph_callees`) is required only for cross-component bugs (Step 2.3) — not for local fixes.

## Step 1: Create Plan File Header (FIRST)

1. **Parse flags** from arguments: `--worktree=yes|no` or `--new-branch` (default: `No`). Strip the flag.
2a. **Create new branch (if `--new-branch`):**

   **Step 1 — Stash any uncommitted work** (prevents checkout conflicts):
   ```bash
   STASH_MSG="pilot-spec-$(date +%s)"
   git stash push -m "$STASH_MSG" --include-untracked 2>/dev/null
   STASHED=$?  # 0 = stashed something, 1 = nothing to stash
   ```

   **Step 2 — Detect default branch** (local-only, no network dependency):
   ```bash
   git fetch origin 2>/dev/null
   DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
   DEFAULT_BRANCH=${DEFAULT_BRANCH:-main}
   ```

   **Step 3 — Create and checkout the branch** (handle name collisions):
   ```bash
   BRANCH_NAME="fix/<plan_slug>"
   # If branch already exists, append short timestamp
   if git rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
     BRANCH_NAME="fix/<plan_slug>-$(date +%m%d-%H%M)"
   fi
   git checkout -b "$BRANCH_NAME" "origin/$DEFAULT_BRANCH"
   ```

   **Step 4 — Restore stash on failure:**
   ```bash
   # If checkout failed and we stashed, restore the stash
   if [ $? -ne 0 ] && [ "$STASHED" -eq 0 ]; then
     git stash pop 2>/dev/null
   fi
   ```

   `<plan_slug>` is derived from the bug description (same slug used for the plan filename). If checkout fails even after stashing, warn the user and fall back to current branch — the stash is restored automatically. After branch creation, continue with `Worktree: No` semantics. The stash remains in `git stash list` for manual recovery if needed.
2b. **Create worktree early (if `--worktree=yes`):** Same pattern as spec-plan Step 2.
3. **Generate filename:** `docs/plans/YYYY-MM-DD-<bug-slug>.md`
4. **Fetch author email** (best-effort): same as spec-plan Step 2 step 4. If non-empty, include `Author: <email>` in header. If empty/fails, omit.
5. **Write header:**

   ```markdown
   # [Bug Description] Fix Plan

   Created: [Date]
   Author: [email if available]
   Status: PENDING
   Approved: No
   Iterations: 0
   Worktree: [Yes|No]
   Type: Bugfix

   > Investigating bug...

   ## Summary

   **Symptom:** [Bug description from user]

   ---

   _Tracing root cause..._
   ```

6. **Register:** `~/.pilot/bin/pilot register-plan "<plan_path>" "PENDING" 2>/dev/null || true`

## Step 2: Root Cause Investigation

Complete each sub-step before the next. No shortcuts.

### 2.1 Reproduce & understand

- Restate **symptom** (what user observes), **trigger** (when/how), **expected behaviour**.
- Vague? One focused `AskUserQuestion`.
- Reliable repro? Steps?
- **Not reproducible after 2 attempts:** STOP guessing. `AskUserQuestion` for the missing signal — exact command, input, environment, stack trace, or recording.
- **Intermittent (flaky / race):** trigger 10+ times, record state at failure. Flaky bugs need a test that **forces** the race (deterministic ordering, frozen clock, blocked event loop), not one that hopes to hit it.

### 2.2 Recent changes

- `git log --oneline -10 -- <file>`, `git diff` for the obvious suspects.
- **A specific token appeared/disappeared?** `git log -S "<string>" -- <path>` (added/removed). Regex: `git log -G "<pattern>"`. Faster than bisect when correlated with a symbol.
- New deps, config changes, env differences?

### 2.3 Trace the root cause

**Start with `codegraph_context(task="<bug description and symptoms>")`** — single call, returns entry points, related symbols, and code context. Read it before going deeper.

**Deep dive when needed:** `codegraph_search` to find a specific symbol, then `codegraph_explore(query="<symbol names>")` for full source from all relevant files in one call.

**Backward tracing (symptom → source):**

1. Find where the wrong behaviour appears — note `file:line`.
2. `codegraph_callers` traces what called this with the bad value/state.
3. Keep tracing until you find the **source** where the bad data originates.
4. **Fix at the source, not where the error appears.**

**Multi-component systems — instrument at boundaries before concluding:**

```bash
# Layer 1: entry point
echo "=== enter handler — input: ==="
echo "$INPUT"

# Layer 2: business logic
echo "=== leave handler / enter service — payload: ==="
jq . <<< "$PAYLOAD"

# Layer 3: storage
echo "=== query result: ==="
psql -c "SELECT id, status FROM jobs WHERE id=$JOB_ID"
```

This reveals **which** layer breaks. Investigate that layer next — don't speculate across layers.

**⛔ Mark every temporary log/print with `SPEC-DEBUG:`** (e.g. `console.log("SPEC-DEBUG: filters=", filters)`, `# SPEC-DEBUG: print(x)`). Verification greps the diff for this marker — any match fails verification and forces cleanup. Only way temporary diagnostics are allowed in the fix diff.

**Structural tracing — proportional to bug scope.** For bugs spanning 2+ files, modules, or components, run `codegraph_callers` + `codegraph_callees` on the root-cause function plus `codegraph_impact` for blast radius. For local bugs (typo, off-by-one, wrong constant in one function, missing null check at one call site), `codegraph_context` from above plus a targeted Read is enough — skip the full call-graph traversal.

Tools: CodeGraph, Semble (`semble search`/`semble find-related` or `mcp__semble__search`/`mcp__semble__find_related`), Read/Grep/Glob for exact patterns.

### 2.4 Pattern analysis

1. Find **working examples** — similar code in the codebase that works correctly.
2. Compare: what's different between working and broken?
3. List every difference — don't assume "that can't matter".

### 2.5 Root cause statement

State clearly:

- **Root cause:** `file/path.py:lineN` — `function_name()` does X but should do Y
- **Why:** WHY it causes the symptom (not just what is wrong)
- **Confidence:** High (traced fully) / Medium (strong hypothesis) / Low (needs more data)

Low confidence → gather more evidence. Don't guess.

**Escalation:** if 3+ hypotheses have failed, this is likely architectural. STOP and `AskUserQuestion` before continuing.

## Step 3: Plan the Fix

### Gate — before writing the plan

Answer YES to all:

1. Root cause stated as `file:lineN — function() does X but should do Y`?
2. WHY it causes the symptom is explained?
3. Confidence is High or Medium?

If any NO → return to Step 2.

### Fix approach selection

**Default: pick the obvious fix.** For most bugs the source-level change at the root cause is the only reasonable fix. Document it in one or two sentences and move on. Don't manufacture fake alternatives.

**Propose 2–3 approaches only when there is a genuine architectural choice** (patch at call site vs. fix at source vs. add validation layer, with materially different scope/regression/maintenance trade-offs). For each: name, what it fixes, trade-offs, recommendation.

**⛔ Ground approach labels in the root cause.** Step 2.5 already produced a concrete `Root Cause: file:line — function_name()` statement and Step 2.3 ran `codegraph_context`. When proposing alternatives, option labels must reference the actual symbols/files involved — e.g., `Patch at OrderHandler.validate (call site, src/handlers/order.py:88)` vs. `Fix at source OrderValidator.check (src/validators/order.py:42)`. Generic labels ("patch at call site" / "fix at source") with no symbol names are a regression — the data to ground them is already in your investigation notes.

When a genuine choice exists AND `PILOT_PLAN_QUESTIONS_ENABLED` is not `"false"`: use `AskUserQuestion` to pick.

```bash
~/.pilot/bin/pilot notify plan_approval "Fix Approach" "<plan-slug> — fix strategy" --plan-path "<plan_path>" 2>/dev/null || true
```

### Behavior Contract (MANDATORY)

```markdown
## Behavior Contract

**Given:** [precondition / state / input that triggers the bug]
**When:** [the action or call that exercises the code path]
**Currently (bug):** [actual, incorrect behavior — the symptom]
**Expected (fix):** [correct behavior the fix must produce]
**Anti-regression:** [named tests / flows / API contracts that must still pass]
```

`Anti-regression:` must name specific tests or flows — `test_search_with_filters_returns_200, test_search_pagination` not "existing search tests".

### Behavior Contract — completeness probe

Before locking the contract, work backward once: does the bug have a sibling that the current `Expected (fix):` does not cover? Walk these three prompts:

1. **What boundary inputs share the buggy code path?** Empty, zero, negative, max length, unicode, whitespace-only, duplicate, exactly-at-limit. If the bug repros on `""` but the contract only names "invalid input", tighten the language.
2. **Are there cancel / abort variants?** If the buggy path is user-initiated, is the cancel path also broken or already correct?
3. **Are there concurrency edges?** If two callers exercise the path simultaneously, does the bug surface only under contention, or only in isolation? The contract should name which.

For each gap found, either extend `Expected (fix):` to cover it OR document why it's out of scope in `## Investigation`. The reproducing test (Task 1) only catches what the contract names — gaps here become regression-prone follow-up bugs.

### Task structure — three tasks, no exceptions

⛔ Do NOT merge tasks. Separate checkboxes = separate proof.

**Task 1 — Write Reproducing Test (RED)**
Encode `Currently → Expected` via an existing public entry point. Run → must FAIL with the documented symptom. Worktree mode: commit alone before any fix code. Naming: `test_<function>_<bug>_<expected>`.

**Reuse > create.** If a test class already exists for this entry point, modify it (add one new test method that encodes the bug). Do NOT create a sister test class — that violates the parsimony rule (see `pilot/rules/testing.md` § Test Parsimony).

**`Trivial:` does not apply here.** The feature TDD loop's `Trivial:` escape (see `pilot/skills/spec-implement/steps/02-tdd-loop.md`) is feature-only. Bugfixes always require a reproducing RED test regardless of diff size — that is the bugfix lane's anti-regression guarantee, and removing it would destroy the lane's value.

**Task 2 — Implement Fix at Root Cause**
Minimal change at `Root Cause: file:line`. Fix at source, not symptom. Re-run reproducing test → must PASS. Run targeted test module(s), not full suite — full suite runs at Task 3. Diff must touch the root-cause file.

**Task 3 — Quality Gate**
Lint, type check, build (if applicable). Re-run full suite at the END (lint/type auto-fixes can break tests). UI-facing bugs: the Verification Scenario runs in verify phase, not here.

**Scope scaling:** simple bugs get short tasks, complex bugs get longer tasks — but always three tasks.

**Defense-in-depth:** when the bug propagated through multiple layers, plan validation at each layer (entry point, business logic, environment guards). Document as `Defense-in-depth:` in the Fix Approach section.

### Verification Scenario (UI-facing bugs only)

```markdown
### TS-001: [Bug Trigger / Fix Confirmation]
**Preconditions:** [State that triggers the bug]

| Step | Action | Expected Result (after fix) |
|------|--------|-----------------------------|
| 1 | [User action that triggered bug] | [Correct behavior now shown] |
| 2 | [Follow-up verification] | [No regression] |
```

Tool-agnostic — Claude Code Chrome, Chrome DevTools MCP, playwright-cli, or agent-browser per `browser-automation.md`.

## Step 4: Write the Bugfix Plan

**Save to:** `docs/plans/YYYY-MM-DD-<bug-name>.md`

```markdown
# [Bug Description] Fix Plan

Created: [Date]
Status: PENDING
Approved: No
Iterations: 0
Worktree: [Yes|No]
Type: Bugfix

## Summary

**Symptom:** [What user observes]
**Trigger:** [When/how it happens]
**Root Cause:** `file/path.py:lineN` — [what's wrong and why]

## Investigation

- [Key findings from tracing — breadcrumb trail so implementer understands the bug]
- [Working example for comparison, if relevant]
- [Recent changes that may have caused it, if relevant]

## Behavior Contract

**Given:** [precondition / state / input that triggers the bug]
**When:** [the action or call that exercises the code path]
**Currently (bug):** [actual, incorrect behavior — the symptom]
**Expected (fix):** [correct behavior the fix must produce]
**Anti-regression:** [what must still work — behavior the fix must NOT break]

## Fix Approach

**Chosen:** [Name of selected approach]
**Why:** [1-2 sentences — what it fixes and what it costs. If a rejected option is one an implementer might re-derive, mention the rejection in one half-sentence here. Do NOT add a separate Alternatives list.]

**Files:** [files to modify]
**Strategy:** [how to fix — reference pattern from working code if applicable]
**Tests:** [test files to create/modify — MUST exist before any fix code]
**Defense-in-depth:** [additional validation layers, if applicable — skip for isolated fixes]

## Verification Scenario (only for UI-facing bugs — omit otherwise)

### TS-001: [Bug Trigger / Fix Confirmation]
**Preconditions:** [State that triggers the bug]

| Step | Action | Expected Result (after fix) |
|------|--------|-----------------------------|
| 1 | [User action that triggered bug] | [Correct behavior] |
| 2 | [Follow-up verification] | [No regression] |

## Tasks

> Always 3 tasks below. Their checkboxes are the progress tracker — no separate `## Progress` section needed.

### Task 1: Write Reproducing Test (RED)

**Objective:** Encode the Behavior Contract as a failing test BEFORE writing any fix code.
**Files:** [test files to create/modify]
**Entry point:** [public function or endpoint the test exercises — not internal helpers]
**DoD:** Test exists, named `test_<function>_<bug>_<expected>`, runs, fails with an error matching the documented `Currently (bug)` behavior. In worktree mode: committed as its own commit.
**Verify:** `[command that runs ONLY this test — must FAIL]`

### Task 2: Implement Fix at Root Cause

**Objective:** Minimal change at `Root Cause: file:line` that makes the reproducing test pass without breaking `Anti-regression`.
**Files:** [files to modify — must include the root cause file]
**Strategy:** [how the fix satisfies the Behavior Contract — fix at source, not at symptom]
**DoD:** Reproducing test PASSES. Full test suite PASSES (anti-regression gate for the fix). Diff touches the root-cause file. No try/except wrappers hiding the bad value; no callsite patches around the symptom.
**Verify:** `[command that runs the reproducing test — must PASS]`

### Task 3: Quality Gate

**Objective:** Lint + type check + build clean, with the full suite re-run to catch regressions introduced by any auto-fixes applied in this task.
**DoD:** Lint clean, type check clean, build green (if applicable), full suite green. Performance audit passed (no expensive uncached work on hot paths in the diff).
**Verify:** `[lint] && [type check] && [build if applicable] && [full suite command]`

**Why the suite runs again here:** lint/type checkers and formatters may auto-modify code (imports, type annotations, whitespace). A checkbox marked green should mean "suite green AFTER this task's code touches." The verify phase then runs it once more as the authoritative signal — that small redundancy is quality insurance, not waste.
```

**Always three tasks.** Never collapse Task 1 + Task 2 into "Fix (test + code)". The separation is what prevents "I'll just write the code and add a test after."

**Do NOT include:** "Goal Verification" sections, "Risks and Mitigations" table, "Assumptions" section, per-task "Dependencies" field.

**Include `## Verification Scenario` only for UI-facing bugs** (from the Verification Scenario guidance in Step 3). Omit entirely for backend/non-UI bugs.

**The `## Behavior Contract` section is MANDATORY for every bugfix plan** — it is the source of truth for what the reproducing test encodes and what verification audits.

## Step 5: Check for Console Annotation Feedback (Before Approval)

**⛔ Run this BEFORE Step 6 (approval).** Check if the user has annotated the plan in the Console's Specifications tab. Annotations auto-save to JSON — no "Send Feedback" button needed.

1. Derive annotation file: `docs/plans/.annotations/<plan-filename>.json`
2. Read the annotation file with the Read tool. If the file doesn't exist, treat as `NO_FEEDBACK`. If it exists, check whether `planAnnotations` has any entries (`FEEDBACK_EXISTS`) or is empty/missing (`NO_FEEDBACK`).
3. **If `FEEDBACK_EXISTS`:** Each annotation in `planAnnotations` has `originalText` (selected passage) and `text` (user's note). Incorporate into plan, delete the annotation file via `rm -f "<annotation-file-path>"` (e.g. `rm -f "docs/plans/.annotations/2026-03-26-my-bug.json"`), note changes. Proceed to Step 6.
4. **If `NO_FEEDBACK`:** proceed directly to Step 6.

## Step 6: Get User Approval

**⛔ If `PILOT_PLAN_APPROVAL_ENABLED` is `"false"` (from Step 0),** skip this step: set `Approved: Yes` in the plan file automatically and immediately invoke `Skill(skill='spec-implement', args='<plan-path>')`. No AskUserQuestion, no notification.

**When `PILOT_PLAN_APPROVAL_ENABLED` is NOT `"false"`:**

0. Notify:
   ```bash
   ~/.pilot/bin/pilot notify plan_approval "Bugfix Plan Ready" "<plan-slug> — annotate in Console or approve here" --plan-path "<plan_path>" 2>/dev/null || true
   ```
1. Summarize: symptom → root cause → fix approach → task structure
2. AskUserQuestion:
   - "Yes, proceed" — Approve as-is and start spec-implement
   - "No, I have feedback" — I've annotated in the Console or edited the plan file; process my feedback

   The user can pause at this prompt, annotate in the Console's Specifications tab (auto-saves), or edit the plan file directly, then pick option 2. No "ready" handshake required.
3. **Yes:** Set `Approved: Yes`, invoke `Skill(skill='spec-implement', args='<plan-path>')`
   **No, I have feedback:** Re-run Step 5 (process Console annotations), re-read the plan file (in case the user edited it), then return to Step 6 and ask again.
   **Other free-text feedback:** Incorporate the changes into the plan, then re-ask with a fresh AskUserQuestion.