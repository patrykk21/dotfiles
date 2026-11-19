---
name: spec-verify
description: "Spec verification phase - tests, execution, rules audit, code review"
argument-hint: "<path/to/plan.md>"
user-invocable: false
---

# /spec-verify - Verification Phase

**Phase 3 of the /spec workflow (features).** Runs comprehensive verification: automated checks, code review, program execution, and E2E tests. For bugfix plans, use `spec-bugfix-verify` instead.

**Input:** Plan file with `Status: COMPLETE`
**Output:** Plan status → VERIFIED (success) or loop back to implementation (failure)

---

## ⛔ KEY CONSTRAINTS

<!-- CC-ONLY -->
1. **Run code review when enabled** — Step 1 launches `changes-review` via `Task(subagent_type="changes-review")` when `PILOT_CHANGES_REVIEW_ENABLED` is not `"false"` (read in Step 0). To disable, use Console Settings → Reviewers → Changes Review toggle.
2. **Only changes-review — NEVER spec-review** — Do NOT launch `spec-review` during verification. Do NOT read or reference `findings-spec-review-*.json` files — they are stale artifacts from the planning phase that were already addressed during implementation. If you encounter a spec-review findings file, **ignore it completely**.
<!-- /CC-ONLY -->
<!-- CODEX-START
1. **Run native Codex changes review when enabled** — Step 1 launches the managed `changes-review` custom agent via `multi_agent_v1.spawn_agent` when `PILOT_CHANGES_REVIEW_ENABLED` is not `"false"` (read in Step 0). Step 3 waits for and applies its findings.
2. **Only changes-review — NEVER spec-review** — Do NOT launch `spec-review` during verification. Planning findings are stale artifacts from the planning phase and must be ignored.
CODEX-END -->
3. **NO stopping** — Everything automatic. Never ask "Should I fix these?"
4. **Fix ALL findings** — must_fix AND should_fix. No permission needed.
5. **Code changes finish BEFORE runtime testing** — Phase A then Phase B.
6. **Plan file is source of truth** — re-read it after auto-compaction, don't rely on conversation memory.
7. **Re-verification after fixes is MANDATORY** — fixes can introduce new bugs.
8. **Quality over speed** — never rush due to context pressure.

## Step 0: Setup, Process Overview, & Runtime Classification

### 0.1 Read Toggle Configuration

**Run first, before any other step.** Read the reviewer toggle env vars:

<!-- CC-ONLY -->
```bash
echo "REVIEWER=$PILOT_CHANGES_REVIEW_ENABLED CODEX_CHG=$PILOT_CODEX_CHANGES_REVIEW_ENABLED"
```

Codex reviewers are controlled entirely by Console Settings — the env vars are authoritative.

Reference these values in Steps 1 (Launch Review), 3 (Collect Results — Codex collection).
<!-- /CC-ONLY -->
<!-- CODEX-START
```bash
echo "REVIEWER=$PILOT_CHANGES_REVIEW_ENABLED"
```

Native Codex changes review is controlled by the regular reviewer toggle. Reference this value in Steps 1 and 3.
CODEX-END -->

### 0.2 Process Overview

```
Phase A — Finalize the code:
  Launch Reviewer → Automated Checks (tests + lint + verify commands) → Feature Parity (if migration) → Collect Review Results → Fix

Phase B — Verify the running program (depth depends on runtime profile):
  Build → Program Execution → Per-Task DoD Audit → E2E

Final:
  Regression check → Worktree sync → Post-merge verification → Update status
```

### 0.3 Classify Runtime Profile

**Determine verification depth based on what changed:**

| Profile | Criteria | Phase B Scope |
|---------|----------|---------------|
| **Minimal** | No server, no UI, no built artifacts (libraries, CLI tools, hooks, scripts) | Build check only |
| **API** | Server/API but no frontend changes | Build + program execution + DoD audit. Skip E2E. |
| **Full** | Frontend/UI changes or complex deployment | All Phase B steps |

Read the plan's Runtime Environment section (if present) and the changed file types to classify.

## Phase A — Finalize the Code

## Step 1: Launch Code Review Agent (Early)

### 1a: Clean Up Stale Spec-Review Findings (always run, before any launch)

**Always run this first** — regardless of whether changes-review is enabled. Spec-review findings are stale artifacts from the planning phase that were already addressed during implementation.

```bash
SESS_DIR="$HOME/.pilot/sessions/${PILOT_SESSION_ID:-default}"
test -d "$SESS_DIR" && find "$SESS_DIR" -maxdepth 1 -name 'findings-spec-review-*.json' -delete
```

---

<!-- CC-ONLY -->
**If `PILOT_CHANGES_REVIEW_ENABLED` is `"false"` (from Step 0),** skip the rest of this step and proceed to Step 2. (Automated checks in Step 2 still run; only the agent-based review is skipped.)

**When enabled:** Launch the reviewer IMMEDIATELY — it works in the background while you run automated checks.

#### 1b: Gather Context

```bash
git status --short  # Changed files
echo $PILOT_SESSION_ID
```

**Validate session ID:** If `$PILOT_SESSION_ID` is empty, fall back to `"default"` to avoid writing to `~/.pilot/sessions//`.

Collect: changed files list, test framework constraints, runtime environment info, plan risks section.

**Derive plan slug** from the plan filename: strip the date prefix (`YYYY-MM-DD-`) and `.md` extension. Example: `2026-03-02-sku-builder-modal-cleanup.md` → `sku-builder-modal-cleanup`.

Output path: `~/.pilot/sessions/<session-id>/findings-changes-review-<plan-slug>.json`

#### 1c: Launch

**Delete stale changes-review findings before launching** (previous run may have left a file):

```bash
SESS_DIR="$HOME/.pilot/sessions/${PILOT_SESSION_ID:-default}"
test -d "$SESS_DIR" && find "$SESS_DIR" -maxdepth 1 -name 'findings-changes-review-*.json' -delete
```

```
Task(
  subagent_type="changes-review",
  run_in_background=true,
  prompt="""
  **Plan file:** <plan-path>
  **User request:** <original task description that invoked /spec>
  **Changed files:** [file list]
  **Output path:** <absolute path to findings JSON>
  **Runtime environment:** [how to start, port, deploy path]
  **Test framework constraints:** [what it can/cannot test]

  Review implementation: compliance (plan match + user request match), quality (security, bugs, tests, performance), goal (achievement, artifacts, wiring).
  Performance: check for expensive uncached work on hot paths, heavy dependency imports with lighter alternatives, and repeated invocations that redo work when input hasn't changed.
  Write findings JSON to output_path using Write tool.
  IMPORTANT: Include the plan file path in your output JSON as the "plan_file" field.
  """
)
```

**Do NOT wait.** Proceed to Codex launch (if enabled) or Step 2 immediately.

#### Codex Adversarial Review (Optional — launch immediately after Claude reviewer)

**If `PILOT_CODEX_CHANGES_REVIEW_ENABLED` is `"true"` (from Step 0):**

Launch Codex review NOW — it runs in parallel with the Claude reviewer above.

**Codex-once rule.** Codex runs at most once per `/spec` invocation. Before launching, check the sentinel file. If it exists, the review already ran in this session — skip the launch and the collection sub-step in Step 3. Verify-phase iterations (re-verify after fixing findings, code-review-gate annotation fixes) do NOT trigger another Codex run.

```bash
SESS_ID="${PILOT_SESSION_ID:-default}"
CODEX_FLAG="$HOME/.pilot/sessions/$SESS_ID/codex-changes-review-ran-<plan-slug>.flag"
if [ -f "$CODEX_FLAG" ]; then
  echo "Codex already reviewed this plan in this session — skipping (codex-once)."
  # Skip the launch below and the Codex collection sub-step in Step 3.
fi
```

1. Detect companion path and ensure project root:
```bash
CODEX_COMPANION=$(ls ~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs 2>/dev/null | sort -V | tail -1)
PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-$(pwd)}"
```

2. Build the review prompt file by rendering the **template at `$HOME/.claude/agents/changes-review-codex.md`**. The template is the single source of truth for code-review semantics — do NOT re-state the prompt inline in this skill. Substitute four placeholders:
   - `{{PLAN_PATH}}` — absolute path to the plan file
   - `{{PLAN_GOAL}}` — the 1–2 sentence Goal sentence from the plan's `## Summary`
   - `{{BASE_REF}}` — `main` (or the worktree base branch detected via `pilot worktree status --json`)
   - `{{CHANGED_FILES}}` — newline-separated paths to the files the plan said it would touch (extracted from each task's `Files:` block)

```bash
PROMPT_TEMPLATE="$HOME/.claude/agents/changes-review-codex.md"
PROMPT_FILE="/tmp/codex-changes-review-${PILOT_SESSION_ID:-default}-<plan-slug>.md"

PLAN_PATH="/absolute/path/to/docs/plans/YYYY-MM-DD-<slug>.md"
PLAN_GOAL="<one or two sentences from the plan Summary>"
BASE_REF="main"
CHANGED_FILES=$(printf -- '- %s\n' \
  path/to/changed/file-1 \
  path/to/changed/file-2)

PLAN_PATH="$PLAN_PATH" PLAN_GOAL="$PLAN_GOAL" BASE_REF="$BASE_REF" CHANGED_FILES="$CHANGED_FILES" \
PROMPT_TEMPLATE="$PROMPT_TEMPLATE" PROMPT_FILE="$PROMPT_FILE" \
uv run --no-project python -c '
import os, pathlib
text = pathlib.Path(os.environ["PROMPT_TEMPLATE"]).read_text()
for key in ("PLAN_PATH", "PLAN_GOAL", "BASE_REF", "CHANGED_FILES"):
    text = text.replace("{{" + key + "}}", os.environ[key])
pathlib.Path(os.environ["PROMPT_FILE"]).write_text(text)
'
```

3. Launch the task in background. **For `task`, the companion's `--background` flag IS supported** (unlike `review`/`adversarial-review`). Use the companion's own background mode — the launch command returns the job ID immediately on stdout. Capture the job ID for collection in Step 3.

   ```
   Bash(
     command="cd $PROJECT_ROOT && node $CODEX_COMPANION task --background --prompt-file \"$PROMPT_FILE\"",
     run_in_background=false,
     timeout=60000
   )
   ```

   The stdout looks like: `Codex Task started in the background as task-<id>. Check /codex:status task-<id> for progress.` Extract the `task-…` token and store as `JOB_ID`.

   **Verify registration before letting Step 3 poll** — fail-fast guard against synthetic-ID launches:

   ```bash
   node "$CODEX_COMPANION" status "$JOB_ID" --json 2>/dev/null | grep -q '"status":' \
     || { echo "Codex launch did not register with broker — JOB_ID is synthetic. Skipping Codex this run."; JOB_ID=""; }
   ```

   If `$JOB_ID` is empty after this check, skip Step 3 polling and proceed with Claude reviewer only.

**Do NOT wait** — proceed to Step 2 immediately. You'll be notified when the polling bash (Step 3) completes.
<!-- /CC-ONLY -->
<!-- CODEX-START
**If `PILOT_CHANGES_REVIEW_ENABLED` is `"false"` (from Step 0),** skip the rest of this step and proceed directly to Step 2 (Automated Checks).

**When enabled:** launch the managed Codex custom agent immediately. It runs while automated checks execute in Step 2.

Gather context first:

```bash
git status --short
```

Collect: changed files list, runtime environment info, test framework constraints, and plan risks section. Derive the plan slug from the plan filename by stripping the date prefix and `.md`.

Persist the returned agent id so Step 3 can survive long checks or compaction. Use a deterministic session file:

```bash
SESS_DIR="$HOME/.pilot/sessions/${PILOT_SESSION_ID:-default}"
AGENT_ID_FILE="$SESS_DIR/changes-review-agent-id-<plan-slug>.txt"
mkdir -p "$SESS_DIR"
```

```python
review = multi_agent_v1.spawn_agent(
    agent_type="changes-review",
    message="""
    Plan file: <plan-path>
    User request: <original task description that invoked $spec>
    Changed files: [file list]
    Runtime environment: [how to start, port, deploy path]
    Test framework constraints: [what it can/cannot test]

    Review implementation: compliance, quality, and goal achievement.
    Return ONLY valid JSON matching the changes-review schema.
    Include the plan file path in the `plan_file` field.
    """,
)
CHANGES_REVIEW_AGENT_ID = review.agent_id
```

After spawning, write `CHANGES_REVIEW_AGENT_ID` to `$AGENT_ID_FILE`.

Do NOT wait here. Proceed directly to Step 2.

Self-review the implementation diff before proceeding: `git diff --stat` to verify scope matches the plan, and spot-check changed files for obvious issues (security, missing error handling, dead code).
CODEX-END -->

## Step 2: Automated Checks

Run all mechanical checks in sequence. Fix any failures before proceeding.

1. **Full test suite** — `uv run pytest -q` / `bun test` / `npm test`. Fix failures immediately.
2. **Type checker** — `basedpyright` / `tsc --noEmit`. Zero errors required.
3. **Linter** — `ruff check` / `eslint`. Errors are blockers, warnings acceptable.
4. **Coverage** — If the project already has coverage tooling, or the task touches critical paths (business logic, security, data integrity, error handling), run the existing coverage command and inspect the report. **No blanket numeric gate.** If a critical path's coverage or explicit behaviour coverage dropped vs main, fix it. Glue/CRUD/UI-binding files are not gated, and do not add coverage tooling just to satisfy this step.
5. **Test Parsimony Audit** — For each task whose `Files:` block adds new test files, group new test classes by production class/entry point and count only classes added by this task. If any production class has more than 2 new test classes (1 unit + 1 functional/integration) AND the task does not declare a `Why >2 test classes:` note in Key Decisions, flag as **must_fix** and return to spec-implement. Also scan new test files for: (i) per-method test classes (e.g. `DoSomethingTests` for class `Foo` with method `DoSomething`) — flag as **must_fix**; (ii) two or more tests asserting the same observable behaviour through different internal paths — flag as **should_fix**. The `changes-review` reviewer does the same audit independently in Phase A; this step is the verifier's first pass.

   **2.1. `Trivial:` claim audit** — For every plan task that declares a `Trivial:` justification, run `git diff <base>..HEAD -- <task's Files: block>` and check the production-code diff against the four parsimony criteria. Flag **must_fix** if any of the following hold:
   - the `Trivial:` field does not name an existing covering test or verification command, OR
   - net added lines of production code > 5 (excluding pure import lines, blank lines, and comment-only lines), OR
   - the diff introduces a new control-flow construct with a non-trivial body — `if/elif/else`, `match`, `for`/`while` loop, `try/except` (a one-line guard like `if x is None: return None` is NOT non-trivial; a multi-line block is), OR
   - the diff adds a new public symbol (function name not starting with `_`, class name not starting with `_`, module-level constant exported via `__all__`), OR
   - the diff adds a new error path (raises a new exception type, returns a new error sentinel, calls `logger.error`/`logger.warning` that did not exist).

   When flagged, the implementer must: remove the `Trivial:` field from the task, write a real RED test, and re-implement the task per the standard TDD loop. This audit is the post-implementation guardrail against the `Trivial:` field being abused to skip TDD; the planner's pre-implementation claim is not authoritative.
6. **Build** — Clean build, zero errors.
7. **File length** — Changed production files (non-test): >800 lines consider splitting, >1000 flag for review.
8. **Plan verify commands** — For each task's `Verify:` section, run each command wrapped in `timeout 30 <cmd> || echo 'TIMEOUT'`. Defer server-dependent commands (containing `curl`, `localhost`, `http://`, browser automation) to Phase B.
9. **Performance audit** — For each changed file on a hot path (UI render, request handler, polling loop, CLI inner loop): is expensive work (parsing, serialization, I/O, dependency loading) cached/memoized? Are heavy dependencies imported fully when lighter alternatives exist? Does repeated invocation redo work when input hasn't changed? **This is a static code review — no running program needed.** Performance issues from missing caching are structural and visible in the source.
10. **Feature Parity Check (migration/refactoring only)** — Skip unless the plan has a `## Feature Inventory` section.
    1. Compare old vs new implementation
    2. Verify each feature exists in new code
    3. Run new code and verify same behavior

    <!-- CC-ONLY -->
    **If features are MISSING:** Run the iteration-cap check from Step 11 first (read `Iterations:` from the plan header; if `>= 3` ask the user Continue / Pivot / Abandon before incrementing). On Continue: add tasks with `[MISSING]` prefix, set `Status: PENDING`, increment `Iterations`, register status change, invoke `Skill(skill='spec-implement', args='<plan-path>')`.
    <!-- /CC-ONLY -->
    <!-- CODEX-START
    **If features are MISSING:** Run the iteration-cap check from Step 11 first (read `Iterations:` from the plan header; if `>= 3` present the user with Continue / Pivot / Abandon options before incrementing). On Continue: add tasks with `[MISSING]` prefix, set `Status: PENDING`, increment `Iterations`, register status change, then continue immediately with the `$spec-implement` skill instructions using arguments: `<plan-path>`.
    CODEX-END -->

## Step 3: Collect Review Results & Re-Verify

<!-- CC-ONLY -->
**If `PILOT_CHANGES_REVIEW_ENABLED` is `"false"` (from Step 0 — Step 1 was skipped),** skip this step entirely and proceed to Step 4 (Phase B). There are no findings to collect.
<!-- /CC-ONLY -->

<!-- CC-ONLY -->
**When enabled — mandatory. Never skip** — even if you're confident, context is high, or tests pass.

**⛔ NEVER use `TaskOutput`** to retrieve results — it dumps the full agent transcript into context, wasting thousands of tokens.

**Wait for Claude reviewer results (bash polling — NOT Read loop):**

```bash
OUTPUT_PATH="<findings-path>"
for i in $(seq 1 250); do [ -f "$OUTPUT_PATH" ] && echo "READY" && break; sleep 2; done
```

Then Read the file once. If not READY after ~8 min, re-launch synchronously.

**Validate findings:** After reading the JSON, verify that the `plan_file` field matches the current plan path. If it doesn't match, the findings are stale from a previous `/spec` — delete the file, re-launch the reviewer, and wait again.

#### Fix Claude Reviewer Findings

**Fix automatically — no user permission needed.**

1. **must_fix** → Fix immediately (security, crashes, TDD violations)
2. **should_fix** → Fix immediately (spec deviations, missing tests, error handling)
3. **suggestions** → Implement if quick

For each fix: implement → run relevant tests → log "Fixed: [title]"

#### Collect Codex Results (if launched)

**⛔ Never skip or defer the Codex review.** If Codex was launched in Step 1, collect and act on its results before proceeding past Step 3. The Codex review runs as a `Bash(run_in_background=true)` — you will be automatically notified when it completes.

**⛔ The completion notification is the ONLY valid signal.** Do NOT read the output file to check if the review is done. The file may contain partial output from an in-progress review — reading it before the notification arrives leads to false conclusions ("no findings" when the review is still running). This is the #1 cause of premature Codex skip.

**⛔ If the notification hasn't arrived yet:** STOP. Do NOT proceed to Phase B, do NOT say "still running, moving on", do NOT read the output file, do NOT conclude the review failed. Wait for the `<task-notification>` with `<status>completed</status>`. If you are tempted to check the file — that is the exact mistake this rule prevents.

**Wait for completion via bash polling**, NOT by reading the state file directly. The polling bash returns when the `task` job's status flips to `completed` or `failed`, triggering the completion notification.

```bash
JOB_ID="<captured-task-id from Step 1>"
for i in $(seq 1 250); do
  STATE=$(node "$CODEX_COMPANION" status "$JOB_ID" --json 2>/dev/null \
    | uv run --no-project python -c "import json,sys
try: print((json.load(sys.stdin).get('job') or {}).get('status') or 'unknown')
except Exception: print('parse_error')" 2>/dev/null)
  case "$STATE" in
    completed)                  echo "READY @ iter=$i"; break ;;
    failed|parse_error|unknown) echo "FAIL state=$STATE iter=$i"; break ;;
  esac
  sleep 4
done
```

Treat `parse_error`/`unknown` as failure (job vanished or broker unreachable) — do NOT continue spinning.
Run this as `Bash(run_in_background=true, timeout=600000)`. Code reviews typically take 2–6 minutes; the 10-minute ceiling is the safety margin.

1. **When (and ONLY when) the completion notification arrives**, fetch the findings via the companion's public interface:

   ```bash
   node "$CODEX_COMPANION" result "$JOB_ID" --json > /tmp/codex-task-result-$$.json
   ```

   Read `/tmp/codex-task-result-$$.json` with the `Read` tool. The relevant fields:
   - `storedJob.status` — must be `"completed"`. If `"failed"`, treat as a re-launch trigger; do not silently proceed.
   - `storedJob.result.rawOutput` — a string containing Codex's response. With our prompt template, this is JSON matching the `{verdict, summary, findings, next_steps}` schema.
   - `storedJob.rendered` — same content rendered for display; useful as a fallback if `rawOutput` is malformed.

2. **Parse `rawOutput` as JSON.** Extract `verdict`, `summary`, `findings`, and `next_steps`. If `JSON.parse` fails (Codex deviated from the schema), fall back to `storedJob.rendered` — surface the rendered text to the user as a suggestion-level finding and continue. Do NOT re-launch on a parse failure; one Codex run per `/spec` is the rule.

   Severity → action map for the parsed findings:
   - `critical` / `high` → must_fix — fix immediately
   - `medium` / `low` → should_fix — fix immediately
   - `info` → suggestion — implement if quick

3. **If `storedJob.status` is `"failed"`** (genuine launch failure, not a timeout): re-launch synchronously (foreground `Bash(timeout=600000)`) and wait for results. If the second attempt also fails, escalate to the user with the captured error — do not silently proceed.

4. **Mark Codex as ran** so re-verify iterations within the same session do not re-run it:
```bash
SESS_ID="${PILOT_SESSION_ID:-default}"
CODEX_FLAG="$HOME/.pilot/sessions/$SESS_ID/codex-changes-review-ran-<plan-slug>.flag"
mkdir -p "$(dirname "$CODEX_FLAG")" && touch "$CODEX_FLAG"
```

5. **Cleanup:** delete the temp prompt file. `$PROMPT_FILE` from Step 1 is not in scope here (different bash invocation), so re-derive the path from the same template Step 1 used:
```bash
rm -f "/tmp/codex-changes-review-${PILOT_SESSION_ID:-default}-<plan-slug>.md"
```

**Report:**
```
## Code Verification Complete
**Issues Found:** X
### Goal Achievement: N/M truths verified
### Must Fix (N) | Should Fix (N) | Suggestions (N)
```

#### Re-verification (Only for Structural Fixes)

**Skip** when fixes were localized (terminology, error handling, test updates, minor bugs). Run tests + lint to confirm, proceed to Phase B.

**Re-verify** when fixes required new functionality, changed APIs, or significant new code paths: re-launch changes-review, fix new findings. Max 2 iterations before adding remaining issues to plan.
<!-- /CC-ONLY -->
<!-- CODEX-START
**If `PILOT_CHANGES_REVIEW_ENABLED` is `"false"` (from Step 0 — Step 1 was skipped),** skip this step entirely and proceed to Step 4 (Phase B).

**When enabled — mandatory. Never skip.** Read the `changes-review` agent id captured in Step 1 from working notes or the session file:

```bash
AGENT_ID_FILE="$HOME/.pilot/sessions/${PILOT_SESSION_ID:-default}/changes-review-agent-id-<plan-slug>.txt"
```

If `CHANGES_REVIEW_AGENT_ID` is missing and the file exists, read the file and use its trimmed contents. If both are missing or empty, re-launch `changes-review` once using the Step 1 prompt, persist the new id to the file, then continue. Do not silently skip review while `PILOT_CHANGES_REVIEW_ENABLED` is enabled.

Wait for the final result:

```python
result = multi_agent_v1.wait_agent(targets=[CHANGES_REVIEW_AGENT_ID], timeout_ms=600000)
```

Parse the agent's final message as JSON. If parsing fails, treat the raw final message as one `suggestion` finding and continue; do not re-launch on parse failure.

Validate `plan_file` matches the current plan. If it does not, discard the stale result and self-review the diff before proceeding.

Severity mapping:
- `must_fix` → fix immediately
- `should_fix` → fix immediately
- `suggestion` → implement if quick

For each fix: implement → run relevant tests → log `Fixed: [title]`.

After all findings are handled, re-run the relevant automated checks from Step 2 before proceeding to Step 4.
CODEX-END -->

## Phase B — Verify the Running Program

All code is finalized. No more code changes except critical bugs found during execution.

**If runtime profile is Minimal:** Run build check (Step 4a), then skip to Final section.

⛔ **For API and Full profiles: before declaring "I can't reach a live instance", run the 4-tier live-target probe in Step 7's sub-step `7a-pre`.** That probe applies to Phase B as a whole, not just to E2E — it tells the model to (1) reuse a running local server, (2) start one if a start command exists, (3) detect deploy backends and attempt a preview deploy with eligible credentials, and only then (4) fall back to unit-only with an explicit recorded gap. Skipping this probe and claiming "no live target available" without naming the tiers attempted is a `must_fix` finding.

## Step 4: Build, Deploy, and Verify Code Identity

#### 4a: Build

Build/compile the project. Verify zero errors.

#### 4b: Deploy (if applicable)

If project builds artifacts deployed separately from source: copy to install location, restart services. Check `ps aux | grep <service>` before restarting shared services.

**For platform deploys (Vercel / Fly / Netlify / etc.):** the live-target probe in `07-e2e-and-final-regression.md` § 7a-pre Tier 3 handles preview deploys automatically. Re-using its credential-detection logic here avoids two divergent code paths.

#### 4c: Code Identity Verification

**⛔ Prove the running instance uses your new code before testing it.**

1. Identify a behavioral change unique to this implementation
2. Craft a request only new code handles correctly (e.g., query with new parameter — new code returns filtered results, old code ignores parameter)
3. If response matches OLD behavior → redeploy, restart, re-verify
4. **Do NOT proceed** to execution testing until code identity is confirmed

## Step 5: Program Execution Verification

**If runtime profile is Minimal:** Skip.

**⚠️ Parallel spec warning:** Before starting a server, check port availability: `lsof -i :<port>`. If another `/spec` session occupies it, wait or use a different port.

- Program starts without errors
- Inspect logs for errors/warnings/stack traces
- **Verify output correctness** — fetch source data independently, compare against program output. If mismatch → BUG.
- Test with real/sample data
- **Performance check (UI changes):** Open the page, monitor for lag or high CPU. Watch for: components rendering expensive operations without `useMemo`/`useCallback`, eager loading of all data on mount (lazy-load instead), missing virtualization for large lists, network request storms (N+1 fetches). If page feels sluggish → profile and fix before proceeding.

**Bugs:** Minor → fix, re-run, continue. Major → add task to plan, set PENDING, loop back to implementation.

## Step 6: Per-Task DoD Audit & Not-Verified Acknowledgment

### 6.1 Per-Task DoD Audit

**If runtime profile is Minimal:** Skip.

For EACH task, verify its Definition of Done criteria against the running program with evidence (command output, API response, screenshot).

If any criterion unmet: fix inline if possible, or add task and loop back.

### 6.2 Not Verified Acknowledgment

List what was **NOT** verified and why. Include in the verification report (Step 10). Every gap must have a reason:

| Not Verified | Reason |
|-------------|--------|
| [criterion or scenario] | No test environment / Out of scope / Untestable statically / Deferred |

"None — all criteria have automated verification" is a valid answer if true. Do not omit this section: absence of acknowledged gaps ≠ absence of real gaps.

## Step 7: E2E Verification & Final Regression

**If runtime profile is not Full:** Skip directly to sub-section 7f (Final Regression). The Full-profile E2E sub-steps below assume a UI/browser entry point.

### ⛔ 7a-pre: Resolve a Live Target Before Touching the Browser

**⛔ MANDATORY — never skip to "unit-verified" without completing this probe.** The single most common verify-phase failure mode is: tests pass, no live server is up, the model concludes "unit-verified" and marks the plan VERIFIED without ever interacting with a deployed instance. The four-tier browser priority below is useless if no URL exists to navigate to. This sub-step exists to force an actual deploy attempt before any "I can't run E2E" claim.

Run the probe in order. The FIRST tier that returns a working URL wins; later tiers exist only as fallbacks.

#### Tier 1 — Reuse an already-running local server

If the plan's `## Runtime Environment` section names a local port:

```bash
PORT="<port from plan, e.g. 41777>"
if curl -s --max-time 3 -o /dev/null -w '%{http_code}' "http://localhost:$PORT/" | grep -qE '^(2|3)'; then
  TARGET_URL="http://localhost:$PORT"
  echo "TIER1_OK $TARGET_URL"
fi
```

When the harness blocks `curl`, substitute `mcp__plugin_pilot_web-fetch__fetch_url` with a 3s timeout.

#### Tier 2 — Start the local dev server yourself

If Tier 1 fails AND the plan's Runtime Environment names a start command (`bun run dev`, `npm run dev`, `vercel dev --listen <port>`, `flask run`, `uvicorn ...`):

<!-- CC-ONLY -->
1. Start in background: `Bash(command="cd <cwd> && <start command>", run_in_background=true, timeout=180000)`
<!-- /CC-ONLY -->
<!-- CODEX-START
1. Start the server as a background process from `<cwd>` using `<start command>`. Use the available background process tool or dev-server workflow, and keep the session id isolated when required by `browser-automation.md`.
CODEX-END -->
2. Poll the health endpoint for up to 60s (200/301/302 = ready)
3. On success: `TARGET_URL=http://localhost:<port>`, proceed
4. On failure: capture the last 30 lines of the background process's output file and INCLUDE THEM in the verification report — do NOT silently drop to Tier 3

#### Tier 3 — Probe deploy credentials and attempt a preview deploy

Generic across deploy backends. Detect from repo:

| Marker file / dir | Backend | Auth-check command | Preview deploy |
|---|---|---|---|
| `vercel.json` / `.vercel/` | Vercel | `vercel whoami` | `vercel deploy --yes` |
| `fly.toml` | Fly.io | `flyctl auth whoami` | `flyctl deploy --strategy immediate` |
| `netlify.toml` / `.netlify/` | Netlify | `netlify status` | `netlify deploy --build` |
| `wrangler.toml` / `wrangler.jsonc` | Cloudflare | `wrangler whoami` | `wrangler deploy --dry-run=false` |
| `render.yaml` | Render | `render whoami` (or skip — Render needs PR) | n/a |
| `cdk.json` / `serverless.yml` | AWS | `aws sts get-caller-identity` | `cdk deploy` / `serverless deploy` |
| `.github/workflows/deploy*.yml` | GitHub Actions | `gh auth status` + `gh workflow run` | trigger workflow + poll |
| `Procfile` | Heroku | `heroku auth:whoami` | `heroku create --no-remote && git push heroku` |

**Probe algorithm:**

1. Detect candidate backends by checking marker files (`ls vercel.json fly.toml ...` or `git ls-files`).
2. For each candidate, run its auth-check command with a short timeout. Authenticated → eligible.
3. If ≥ 1 backend is eligible, pick the first one (or the user-preferred one if the plan / `CLAUDE.md` specifies) and run its preview-deploy command. Capture the resulting URL.
4. **Project-config gotchas to handle automatically:**
   - Vercel projects with a `rootDirectory` set in dashboard need the CLI run from the **repo root** (not the configured root directory), otherwise the CLI duplicates the path. If the first deploy attempt errors with `<path>/<configured-root>` doesn't exist, retry from the repo root.
   - Builds that need a fresh dependency install: pass the appropriate flag (`vercel deploy --build-env INSTALL=true` / `fly deploy --build-only`).
5. On success: `TARGET_URL=<preview URL>`, proceed.
6. If NO backend is eligible (no marker files, OR markers exist but every auth-check fails): produce a one-line probe summary in the verification report (`Deploy probe: vercel auth=missing, fly auth=missing → no live target available`) and proceed to the unit-only fallback below — explicitly acknowledging the gap.

#### Tier 4 — Unit-only fallback (only after Tiers 1–3 above all returned no URL)

⛔ **You MUST have executed Tiers 1, 2, AND 3 above** — and recorded their outcomes — before marking any scenario `UNIT_VERIFIED` instead of `LIVE_PASS`. Document:

```
Live-target probe summary:
- Tier 1 (local port <p>): <FAIL reason or NOT_APPLICABLE>
- Tier 2 (start dev server): <FAIL reason or NOT_ATTEMPTED because Tier 1 succeeded>
- Tier 3 (deploy creds): <backend auth status, deploy outcome, error if any>
- Falling back to UNIT_VERIFIED for the following scenarios: …
```

Failing to record this gap in the verification report is a `must_fix` finding by definition — the next reviewer will treat absence of the summary as silent skip.

### 7a: Resolve Browser Tool

**4-tier priority** (see `browser-automation.md`): Chrome → Chrome DevTools MCP → playwright-cli → agent-browser.

<!-- CC-ONLY -->
1. **Claude Code Chrome:** Check if `mcp__claude-in-chrome__*` tools are in your available/deferred tools list. If available, use Chrome for all E2E steps below. Load tools via `ToolSearch(query="select:mcp__claude-in-chrome__<tool>")`. No session isolation needed.

2. **Chrome DevTools MCP:** If Chrome extension is unavailable, check for `mcp__plugin_chrome-devtools-mcp_chrome-devtools__*` tools. Load via `ToolSearch(query="chrome-devtools-mcp", max_results=30)`. Use `take_snapshot()` for a11y tree with uids, `click(uid=...)` / `fill(uid=...)` for interaction.
<!-- /CC-ONLY -->

3. **playwright-cli (CLI fallback):** If neither Chrome tool is available, use playwright-cli for thorough E2E.
```bash
playwright-cli -s=$PILOT_SESSION_ID open <url>
```

4. **agent-browser (lightweight fallback):** If none of the above are available:
```bash
AB_SESSION="${PILOT_SESSION_ID:-default}"
agent-browser --session "$AB_SESSION" open <url>
```

### 7b: Check for Structured Scenarios

Read the plan's `## E2E Test Scenarios` section (if it exists).

**If structured scenarios exist (TS-NNN format):** Follow 7c below.

**If no structured scenarios:** Fall back to ad-hoc verification — test the primary user workflow (every view, interaction, state transition), then cover edge cases:

| Category | What to test |
|----------|-------------|
| Empty state | No data, no results |
| Invalid input | Bad params, wrong types, injection |
| Stale state | References to deleted data |
| Error state | Backend unreachable |
| Boundary | Max values, zero, single item |

Then skip to 7e (close browser + write results).

### 7c: Execute Structured Scenarios

Execute Critical first, then High, then Medium.

<!-- CC-ONLY -->
Create one task per scenario for tracking:

```
TaskCreate(subject="TS-NNN: [name]", description="[priority] | [preconditions]")
```
<!-- /CC-ONLY -->

**For each scenario:**

<!-- CC-ONLY -->
1. `TaskUpdate → in_progress`
<!-- /CC-ONLY -->
1. Execute each step using the resolved browser tool:
   - **Chrome:** `navigate` to open pages, `read_page` after interactions, `computer`/`form_input` per the step's action
   - **Chrome DevTools MCP:** `navigate_page` to open pages, `take_snapshot` after interactions, `click(uid=...)`/`fill(uid=...)` per the step's action
   - **playwright-cli:** `open`/`goto` to navigate, `snapshot` after interactions, `click`/`fill`/`press` per the step's action (refs are bare: `e1` not `@e1`)
   - **agent-browser:** `open`/`goto` to navigate, `snapshot -i` after interactions, `click`/`fill`/`press` per the step's action (refs use `@`: `@e1`)
   - Verify the expected result by reading the page output
3. **PASS:** All steps match expected results → note `TS-NNN: PASS`
4. **FAIL:** Step result doesn't match expected:
   - Analyze root cause, implement minimal fix, re-run relevant tests (stay in Phase B — no code changes that need re-review)
   - Re-execute the scenario (counts as fix attempt 1)
   - If still failing: implement second fix, re-execute (fix attempt 2)
   - After 2 failed fix attempts: note `TS-NNN: KNOWN_ISSUE — [description]`
<!-- CC-ONLY -->
5. **Critical KNOWN_ISSUE** → run the iteration-cap check from Step 11 (read `Iterations:` from the plan header; if `>= 3` ask the user Continue / Pivot / Abandon before incrementing). On Continue: set `Status: PENDING`, increment `Iterations`, register status change, invoke `Skill(skill='spec-implement', args='<plan-path>')` — do not proceed to VERIFIED. On Pivot/Abandon: do not invoke spec-implement; surface to user per Step 11.
<!-- /CC-ONLY -->
<!-- CODEX-START
5. **Critical KNOWN_ISSUE** → run the iteration-cap check from Step 11 (read `Iterations:` from the plan header; if `>= 3` present the user with Continue / Pivot / Abandon options before incrementing). On Continue: set `Status: PENDING`, increment `Iterations`, register status change, then continue immediately with the `$spec-implement` skill instructions using arguments: `<plan-path>` — do not proceed to VERIFIED. On Pivot/Abandon: do not invoke spec-implement; surface to user per Step 11.
CODEX-END -->
6. **High/Medium KNOWN_ISSUE** → document and continue (non-blocking)

### 7d: Write E2E Results to Plan

After all scenarios are executed, append to the plan file:

```markdown
## E2E Results

| Scenario | Priority | Result | Fix Attempts | Notes |
|----------|----------|--------|--------------|-------|
| TS-001   | Critical | PASS   | 0            |       |
| TS-002   | High     | PASS   | 1            | Fixed: missing validation on empty submit |
| TS-003   | Medium   | KNOWN_ISSUE | 2       | Tooltip misaligned on narrow viewport |
```

### 7e: Close Browser

```bash
# Chrome / Chrome DevTools MCP: no explicit close needed
# playwright-cli: playwright-cli -s=$PILOT_SESSION_ID close
# agent-browser: agent-browser --session "$AB_SESSION" close
```

### 7f: Final Regression

Re-run full test suite + type checker + build one final time. If code changed during Phase B (E2E fixes), this catches regressions. If no code changed, it confirms Phase A's green state — cheap insurance.

## Step 8: Worktree Sync & Post-Merge Verification (if worktree active)

### 8.1 Worktree Sync

1. Extract plan slug from path (strip date prefix and `.md`)

2. Check: `~/.pilot/bin/pilot worktree detect --json <plan_slug>`

3. **If no worktree:** Skip to Step 10.

4. **Save plan to project root** (only if gitignored):
   ```bash
   git -C <project_root> check-ignore -q docs/plans/<plan_filename>
   ```
   If exit 0 (ignored): `cp <worktree_plan_path> <project_root>/docs/plans/<plan_filename>`
   If exit 1 (tracked): skip — the squash merge will bring the updated plan.

5. **Show diff:** `~/.pilot/bin/pilot worktree diff --json <plan_slug>`

6. **Notify and ask:**
   ```bash
   ~/.pilot/bin/pilot notify plan_approval "Worktree Sync" "<plan_name> — approve merge" --plan-path "<plan_path>" 2>/dev/null || true
   ```
   AskUserQuestion: "Yes, squash merge" (Recommended) | "No, keep worktree" | "Discard all changes"

7. **Handle choice:**

   **Squash merge:**
   ```bash
   # ⛔ ALL THREE operations MUST be in ONE Bash call chained with &&
   # If sync fails, cleanup MUST NOT run — otherwise work is lost.
   ~/.pilot/bin/pilot worktree sync --json <plan_slug> && PROJECT_ROOT=$(~/.pilot/bin/pilot worktree cleanup --force --json <plan_slug> | jq -r '.project_root') && cd "$PROJECT_ROOT"
   ```
   ⛔ NEVER split sync, cleanup, or cd into separate Bash calls — compaction between them can cause work loss.
   ⛔ The `&&` chain ensures cleanup only runs after a successful sync.

   **Keep worktree:** Report path, user can sync later. Skip 8.2 below.
   **Discard:** `cleanup --discard` + `cd` in same bash call (no sync needed — `--discard` explicitly allows deleting unmerged work). Skip 8.2 below.

### 8.2 Post-Merge Verification (after squash merge only)

**Mandatory after successful squash merge.** The squash merge can introduce breakage from base branch divergence.

1. Run full test suite
2. Run type checker / linter
3. Build verification
4. Program launch smoke test

If any fails: fix on base branch, re-run, commit fix separately (e.g., `fix: resolve post-merge regression from spec/<slug>`).

**⛔ Do NOT proceed to Step 10 until all post-merge checks pass.**

## Step 9: Check for Code Review Feedback

**Run BEFORE marking VERIFIED.** Check if the user has left code review annotations in the Console's Changes tab. Annotations auto-save to the unified JSON — no "Send Feedback" button needed.

Derive the annotation file path: `docs/plans/.annotations/<plan-filename>.json` (same basename as the plan, `.json` extension).

Read the annotation file with the Read tool. If the file doesn't exist, treat as `NO_ANNOTATIONS_FOUND`. If it exists, check whether `codeReviewAnnotations` has any entries (`ANNOTATIONS_FOUND`) or is empty/missing (`NO_ANNOTATIONS_FOUND`).

**⛔ Absence of annotations ≠ approval.** Annotations are an *optional* inline-comment channel; most users approve verbally via Step 10. Never collapse Step 9 → Step 11 because the file is missing or empty.

**If `ANNOTATIONS_FOUND`:**
1. Each annotation in `codeReviewAnnotations` has `filePath`, `lineStart`, `lineEnd`, `side`, and `text` (user's annotation)
2. Fix all issues raised (each annotation = a required fix at the indicated file/line)
3. Delete the annotation file: `rm -f "<annotation-file-path>"` (e.g. `rm -f "docs/plans/.annotations/2026-03-26-my-feature.json"`). By this phase, plan annotations were already consumed by `spec-plan`, so deleting the whole file is safe. Direct deletion avoids curl which is blocked in several hook environments.
4. Re-run tests and typecheck
5. Continue to Step 10

**If `NO_ANNOTATIONS_FOUND`:** continue to Step 10. **You still MUST run Step 10 (the human gate).**

## Step 10: Code Review Gate (User Confirmation)

**⛔ MANDATORY before marking VERIFIED.** All automated checks pass — but the user should review the actual code changes.

<!-- CC-ONLY -->
**⛔ MUST use `AskUserQuestion`** — the stop guard only allows stopping when it detects this tool in the transcript. Plain text output will cause the stop guard to block session exit while waiting for user feedback.

**⛔ Resume / compaction / idle:** if you wake into a session where the previous Step 10 is unresolved (no in-turn approve keyword received from the user), **re-ask via `AskUserQuestion`**. Do NOT infer approval from "checks all passed," empty annotations, or a long quiet gap. Silence is never approval.
<!-- /CC-ONLY -->
<!-- CODEX-START
**⛔ Present options as numbered text and wait for user response.** Do NOT infer approval from "checks all passed" or silence. Explicit approval keywords required.
CODEX-END -->

1. Notify:
   ```bash
   ~/.pilot/bin/pilot notify plan_approval "Verification Complete — Review Changes" "<plan_name> — please review code in Changes tab" --plan-path "<plan_path>" 2>/dev/null || true
   ```

2. Summarize what was done (brief: changes made, tests passed, issues fixed), then ask:

   ```
   AskUserQuestion(
     question="All automated checks passed. Please review the code changes in the Console's **Changes** tab.\n\nYou can leave inline annotations on specific lines using the **Review** mode toggle — annotations save automatically.\n\n[brief summary of changes]\n\nChoose an option below, or type your feedback directly into the input box (free text works the same as picking 'Manual'):",
     options=["Approve — mark spec as verified", "Fix — address my annotations from the Console", "Manual — I'll test manually and report back"]
   )
   ```

3. Handle response — **match strictly, never auto-approve ambiguous input:**
   - **Approve:** Response is one of: "Approve", "approve", "lgtm", "looks good", "continue", "proceed" → proceed to Step 11
   - **Fix:** Response matches "Fix" or mentions annotations/console feedback → re-run Step 9 (check for code review annotations in JSON), apply fixes, re-run tests, return to Step 10
   - **Manual / custom text:** Response matches "Manual" OR is ANY other free-text/custom input → the user wants to pause. **Do NOT mark VERIFIED. Do NOT change plan status.** Use `AskUserQuestion` again (required so the stop guard allows the user to exit while waiting):
     ```
     AskUserQuestion(
       question="Take your time testing. When you're done, choose an option or describe any issues you found:",
       options=["Approve — mark spec as verified", "Issues found — describe below"]
     )
     ```
     Then **stop and wait** for the user's next message.
   - **⛔ After Manual wait — re-evaluation of follow-up:** When the user responds after a Manual pause:
     - Explicit approval ("approve", "lgtm", "looks good") → proceed to Step 11
     - **Any other content** (error descriptions, screenshots, images, bug reports, or ANY non-approval text) → treat as **bug reports to fix**. Investigate the reported issues, implement fixes, re-run tests, then return to Step 10 (ask again).
   - **⛔ NEVER treat ambiguous or custom responses as approval.** Only the explicit keywords listed under "Approve" advance to Step 11.

## Step 11: Update Plan Status

### ⛔ Precondition Gate — verify ALL THREE before writing `Status: VERIFIED`

1. `AskUserQuestion` was called in **this same conversation turn flow** as part of Step 10 (not a previous, abandoned one).
2. The user's most recent reply contains one of the **explicit approve keywords**: `Approve`, `approve`, `lgtm`, `looks good`, `continue`, `proceed`.
3. That reply arrived **after** the AskUserQuestion call — not before, not as a stale message.

If any of the three is false → return to Step 10 and re-ask. Common traps that DO NOT count as approval: "no annotations in file", "all tests pass", "user has been idle", "session was resumed", "user said 'thanks'/'ok'/anything else."

**When ALL passes AND user approves:**

1. Set `Status: VERIFIED` in plan
2. Register: `~/.pilot/bin/pilot register-plan "<plan_path>" "VERIFIED" 2>/dev/null || true`
3. Report completion with summary:
   ```
   ## Verification Complete
   **Issues Found:** X
   ### Goal Achievement: N/M truths verified
   ### Must Fix (N) | Should Fix (N) | Suggestions (N)
   ### Not Verified: [list items from Step 6.2, or "None"]
   ```

4. **Instruct the user:** Include in your completion message:
   ```
   Run /clear before starting new work — this resets context while keeping project rules loaded.
   ```

**When verification FAILS (missing features, serious bugs — before reaching Step 10):**

⛔ **Iteration cap — check BEFORE re-invoking spec-implement.** Read `Iterations:` from the plan header. If `Iterations >= 3` BEFORE incrementing, stop the verify→implement loop and surface to the user. An infinite verify→implement loop on a feature plan is the single largest token-burn pattern in the workflow — three failed verifications means the plan is wrong, not that one more implement pass will fix it.

<!-- CC-ONLY -->
```
AskUserQuestion(
  question="Three verify iterations have failed for this plan. This pattern usually means the plan's design is incomplete or a verify check is mis-specified — not that one more implement pass will fix it. What now?",
  options=[
    "Continue — try one more iteration (rarely the right answer)",
    "Pivot — let me re-investigate the plan with you",
    "Abandon — leave PENDING, I'll come back to it"
  ]
)
```
<!-- /CC-ONLY -->
<!-- CODEX-START
Present these numbered options and wait for user response:

1. Continue — try one more iteration (rarely the right answer)
2. Pivot — let me re-investigate the plan with you
3. Abandon — leave PENDING, I'll come back to it
CODEX-END -->

Handle:
<!-- CC-ONLY -->
- **Continue:** increment `Iterations`, write `## Verification Gaps`, register status, invoke `Skill(skill='spec-implement', args='<plan-path>')` as below.
<!-- /CC-ONLY -->
<!-- CODEX-START
- **Continue:** increment `Iterations`, write `## Verification Gaps`, register status, then continue immediately with the `$spec-implement` skill instructions using arguments: `<plan-path>`.
CODEX-END -->
- **Pivot:** set `Status: PENDING`, do NOT invoke spec-implement. Tell the user you're standing by for new investigation direction.
- **Abandon:** leave `Status: PENDING`, do not invoke spec-implement. Stop.

**When `Iterations < 3`:**

1. Add fix tasks to plan
2. Set `Status: PENDING`, increment `Iterations`
3. Register: `~/.pilot/bin/pilot register-plan "<plan_path>" "PENDING" 2>/dev/null || true`
4. Write `## Verification Gaps` table to plan (overwrite if exists):
   ```markdown
   | Gap | Type | Severity | Affected Files | Fix Description |
   ```
<!-- CC-ONLY -->
5. Invoke `Skill(skill='spec-implement', args='<plan-path>')`
<!-- /CC-ONLY -->
<!-- CODEX-START
5. Continue immediately with the `$spec-implement` skill instructions using arguments: `<plan-path>`.
CODEX-END -->

ARGUMENTS: $ARGUMENTS