---
name: autopilot
description: "Launch GSD project/milestone in fully autonomous mode, or implement a Jira ticket end-to-end. Pass a Jira URL or GSD args."
argument-hint: "<jira-url | new-project | new-milestone | resume> [--from-phase N] [--no-team] [--no-judge] [@idea-doc.md]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Task
  - TodoWrite
  - AskUserQuestion
  - SlashCommand
  - Agent
  - TeamCreate
  - TeamDelete
  - TaskCreate
  - TaskUpdate
  - TaskGet
  - TaskList
  - SendMessage
  - WebSearch
  - WebFetch
  - mcp__claude_ai_Atlassian__*
  - mcp__github-work__*
  - mcp__github-personal__*
---

<ticket-mode>
## Ticket URL Detection

**BEFORE anything else**, check if `$ARGUMENTS` contains a URL (starts with `http://` or `https://`).

If it does, this is a **ticket implementation task**. Detect the platform from the URL:

| URL pattern | Platform |
|-------------|----------|
| `*.atlassian.net/browse/*` | Jira |
| `app.clickup.com/t/*` | ClickUp |
| `linear.app/*/issue/*` | Linear |
| `github.com/*/issues/*` | GitHub Issue |
| Other URL | Try to fetch and parse as a ticket |

### Step 1: Fetch the ticket
Use the appropriate MCP tools or `WebFetch` to get:
- Title/summary and full description
- Acceptance criteria (if any)
- Comments (for additional context)
- Priority and type
- Estimated complexity (LOC, number of files, dependencies)

For **Jira**: use Atlassian MCP tools (extract ticket key from URL, e.g. `ECH-571` from `.../browse/ECH-571`)
For **ClickUp**: use WebFetch to read the ticket
For **GitHub Issues**: use GitHub MCP tools
For **other platforms**: use WebFetch, parse what you can

### Step 2: Evaluate complexity and choose implementation path

After reading the ticket, decide which path to take:

**Simple ticket** (direct implementation) — use when ALL of these are true:
- Touches 1-3 files
- Single clear change (bug fix, rename, config change, add a field, small UI tweak)
- No new architecture or patterns needed
- Estimated under ~100 LOC
- No database migrations
- No new API endpoints or services

**Complex ticket** (GSD flow) — use when ANY of these are true:
- Touches 4+ files across multiple layers (schema, queries, connectors, services, UI)
- Requires new architecture decisions (new parallel route, new data pipeline, new integration)
- Has multiple acceptance criteria or phases
- Estimated over ~100 LOC
- Requires database schema changes with migrations
- Involves new API endpoints, services, or connectors
- Description explicitly mentions phases, multiple steps, or "spike"

### Path A: Simple ticket (direct implementation)

1. **Read project conventions** — AGENTS.md / CLAUDE.md in the project root
2. **Implement** — write code following project conventions
3. **Verify** — run the project's test, lint, typecheck commands. Fix any errors.
4. **Browser verify** — run `/browser-verify` to visually verify the affected pages. Fix regressions before pushing.
5. **Commit & push** — format: `[TICKET-KEY] Description`. Push to current branch.
6. **Create PR** with:
   - Summary of changes
   - **Screenshots** from `/browser-verify`
   - **Human testing steps** — numbered list a reviewer can follow to verify
   - Do NOT assign the PR
7. **Comment on ticket** — add the PR link and brief summary

### Path B: Complex ticket (GSD flow)

1. **Read project conventions** — AGENTS.md / CLAUDE.md in the project root
2. **Initialize GSD project** — create a `.planning/` directory and run `/gsd:new-project` with the ticket description as the input document. This will:
   - Analyze requirements
   - Create a roadmap with phases
   - Plan each phase with verification criteria
3. **Execute phases** — run `/gsd:execute-phase` for each phase, or `/gsd:run-all` to execute all phases autonomously. Each phase:
   - Plans the implementation
   - Executes with atomic commits
   - Verifies against acceptance criteria
4. **Browser verify** — run `/browser-verify` after the final phase. Fix regressions.
5. **Commit & push** — ensure all phase commits are pushed. Format: `[TICKET-KEY] Description`.
6. **Create PR** with:
   - Summary of changes (reference the GSD phases)
   - **Screenshots** from `/browser-verify`
   - **Human testing steps** — numbered list a reviewer can follow
   - Do NOT assign the PR
7. **Comment on ticket** — add the PR link and brief summary

### Both paths: Self-review before PR

Before creating the PR, do a final self-review against the project's AGENTS.md / CLAUDE.md rules. This is NOT optional — it catches issues before reviewers see them.

**Re-read AGENTS.md/CLAUDE.md** and check your changes against every applicable rule:

1. **Architecture compliance**
   - Services only call connectors, never queries directly
   - Connectors wrap results in `ServerActionResult<T>`
   - No `import from "../../queries/*"` in service files
   - Caching uses `createRequestCache` / `createDbCache`, never raw `cache()`

2. **Code standards**
   - No `any` types
   - No JSDoc comments (TypeScript types are sufficient)
   - No `@deprecated` markers
   - No `AbortSignal` / signal parameters
   - No dynamic imports in Server Actions
   - Naming: PascalCase components, camelCase functions, kebab-case files

3. **Data fetching**
   - Server Actions for data fetching (not API routes) unless external access needed
   - GET for fetching, POST for mutations (REST principles)
   - No backwards-compatibility shims or unused re-exports

4. **Files & structure**
   - No unnecessary new files (prefer editing existing)
   - No documentation files unless explicitly requested
   - No files outside ticket scope modified
   - Changelog updated if user-facing changes

5. **Review your diff** — run `git diff --stat` and `git diff` to see exactly what you're submitting. Look for:
   - Accidental debug logs (`console.log`) left in
   - Commented-out code
   - Files that shouldn't have been modified
   - Missing imports or unused imports

If you find violations, **fix them before creating the PR**. Do not note them as "known issues" — fix them.

### Both paths: Post-PR steps

Note: Jira transitions (In Progress, Code Review) are handled by the autopilot scheduler — do NOT transition tickets yourself.

**On subsequent pushes** (e.g., after fixing review comments): re-run `/browser-verify` before pushing. Update PR description if screenshots change.

### Step 3: Update state marker
**ALWAYS maintain a state marker file**, even if this session wasn't launched by the autopilot scheduler.

First, ensure the marker path is set. If `$AUTOPILOT_STATE_MARKER` is not set, derive it from the current worktree:
```bash
if [ -z "$AUTOPILOT_STATE_MARKER" ]; then
    WORKTREE_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")
    export AUTOPILOT_STATE_MARKER="$HOME/.config/autopilot/markers/${WORKTREE_NAME}.state"
    mkdir -p "$(dirname "$AUTOPILOT_STATE_MARKER")"
fi
```

Then update it throughout your work. Format: `STATE|details`

| State | When to write |
|-------|--------------|
| `working\|description` | When actively coding, testing, committing |
| `awaiting_ci\|PR_URL` | After creating or updating a PR, CI is running |
| `awaiting_review\|PR_URL` | CI passed, waiting for human review (CodeRabbit done, needs assignee review) |
| `approved\|PR_URL` | Reviewer approved, ready to merge (set by scheduler, not by you) |
| `needs_input\|question` | When you need the user to answer something |
| `failed\|reason` | When you cannot complete the task |

After the user responds to a question, transition back to `working|addressing feedback`.

**IMPORTANT:** Before writing to the marker, check if it currently says `merged` or `approved`. If so, do NOT overwrite it — those are terminal states set by the scheduler.

### Step 4: Monitor CI and reviews after PR creation
After setting `awaiting_ci`, **do not stop working**. Actively monitor the PR:

1. **Poll CI status** every 30 seconds using `gh pr checks <number>`. Watch for all checks to complete.
   ```bash
   # Loop until CI finishes
   while true; do
       STATES=$(gh pr checks <PR_NUMBER> --json state -q '.[].state' 2>/dev/null | sort -u)
       if echo "$STATES" | grep -q "PENDING\|QUEUED"; then
           sleep 30
           continue
       fi
       break
   done
   ```

2. **Wait 60 seconds after CI passes** — CodeRabbit marks its check as passed before it finishes posting review comments. Give it time.

3. **Check for review comments** — read the PR reviews and comments:
   ```bash
   gh pr view <PR_NUMBER> --json reviews,comments
   ```

4. **If CodeRabbit or any reviewer requested changes**, update the marker to `working|addressing review comments` and fix the issues. Then push, and go back to step 1.

5. **If all reviews pass or only have minor comments**, update the marker:
   ```bash
   echo "awaiting_review|PR_URL" > "$AUTOPILOT_STATE_MARKER"
   ```
   This means CI passed and you're waiting for the human assignee to review.

This marker is how the tmux worktree picker and autopilot scheduler show your current status. **Always update it.**

### Rules for ticket mode
- Work autonomously, but if genuinely uncertain, ask — the user may be watching
- Do NOT modify files outside ticket scope
- Do NOT amend existing commits
- If the dev server is already running, do not start another one
- Follow ALL project conventions from AGENTS.md / CLAUDE.md

**If `$ARGUMENTS` is a URL, execute the ticket flow above and STOP. Do NOT continue to the GSD flow below.**
</ticket-mode>

<objective>
Run an entire GSD project or milestone autonomously from start to finish. The AI chains through all phases (plan → execute → verify → next phase) without stopping for confirmations. It only interrupts the user when:

1. A `checkpoint:human-action` is encountered (auth gates, physical actions)
2. An unrecoverable error occurs after self-diagnosis attempt
3. A verification loop fails 3 times on the same issue

Everything else — roadmap approval, phase planning approval, checkpoint:human-verify, checkpoint:decision — is auto-approved with best-judgment defaults.
</objective>

<modes>
## Mode Detection

Parse `$ARGUMENTS` to determine mode:

- **`new-project [@doc]`** — Full lifecycle: init project → plan all phases → execute all phases
- **`new-milestone [@doc]`** — New milestone: init milestone → plan phases → execute phases
- **`resume`** — Pick up where autopilot left off (reads STATE.md for position)
- **`--from-phase N`** — Start autonomous execution from phase N (planning already done)
- **`--no-team`** — Disable agent teams and fall back to standard subagents. By default, autopilot uses the **team-with-judge** pattern: agent teams with a dedicated Judge teammate that critically evaluates all work, researches best practices online, and blocks subpar output. Pass `--no-team` to opt out (lower token cost but no quality gate).
- **`--no-judge`** — Use agent teams but without the Judge. Falls back to standard `--team` behavior (teammates coordinate but no critical evaluator).
</modes>

<process>

## Step 1: Configure for Autonomous Execution

Set GSD config to full auto mode. If `.planning/config.json` exists, merge; otherwise these become defaults for project init.

```bash
# Ensure config exists
if [ -f ".planning/config.json" ]; then
  node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" config-set workflow.auto_advance true
  node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" config-set workflow._auto_chain_active true
  node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" config-set gates.confirm_project false
  node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" config-set gates.confirm_phases false
  node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" config-set gates.confirm_roadmap false
  echo "✅ Autopilot config applied"
else
  echo "⏳ Config will be set after project init"
fi
```

Store the fact that autopilot is active so nested workflows can detect it:
```bash
export GSD_AUTOPILOT=true
```

## Step 2: Initialize (if new-project or new-milestone)

**For `new-project`:**
Run `/gsd:new-project --auto` with any provided document reference. The `--auto` flag already skips questioning and auto-approves roadmap/requirements.

After init completes, apply autopilot config (Step 1 commands) since config.json now exists.

**For `new-milestone`:**
Run `/gsd:new-milestone` — auto-approve all gates. When the workflow asks for confirmation, respond with approval.

**For `resume`:**
Read `.planning/STATE.md` to determine current position. Extract last completed phase/plan.

**For `--from-phase N`:**
Skip to Step 4 with starting phase = N.

## Step 3: Determine Phase Range

Read `.planning/ROADMAP.md` to get all phases. Set:
- `START_PHASE` = 1 (or N if `--from-phase N`, or next unfinished if `resume`)
- `END_PHASE` = last phase number in roadmap

## Step 4: Autonomous Phase Loop

For each phase from `START_PHASE` to `END_PHASE`:

### 4a. Plan Phase (if no PLAN.md files exist for this phase)
Run `/gsd:plan-phase <N>` with research and plan-checking based on project config.

The plan-phase workflow has its own verification loop (plan-checker agent). In autopilot:
- If plan-checker passes → continue
- If plan-checker fails → auto-retry (up to 3 attempts, which is the default GSD behavior)
- If 3 failures → **INTERRUPT USER** with diagnosis

After planning completes, re-apply auto_chain flag:
```bash
node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" config-set workflow._auto_chain_active true
```

### 4b. Execute Phase (with Judge-in-the-Loop)

Autopilot uses the **team-with-judge** pattern by default. This means every phase execution includes a dedicated Judge teammate that critically reviews all work, researches best practices, and blocks subpar output.

**Determine team mode from flags:**
- Default (no flags): `--team` + Judge
- `--no-judge`: `--team` without Judge
- `--no-team`: standard subagents, no team, no Judge

**Execution:**

1. Run `/gsd:execute-phase <N> --team` (unless `--no-team`)

2. **If Judge is enabled (default):** After `/gsd:execute-phase` completes each wave, spawn a Judge agent to review the wave's output before proceeding:

   Spawn an Agent (subagent_type: `general-purpose`, name: `phase-<N>-judge`) with this mandate:

   > You are the Judge for autopilot phase <N>. Review ALL code changes produced by this phase's execution.
   >
   > **Your process:**
   > 1. Read every file modified or created in this phase (check git diff or SUMMARY.md files in `.planning/phases/<NN>-*/`)
   > 2. Evaluate against: correctness, best practices, security (OWASP), performance, maintainability, consistency with codebase, completeness
   > 3. **Research online** (WebSearch) when uncertain — search for how established projects/frameworks handle similar problems. This is MANDATORY at least once per review.
   > 4. For each issue found, provide: file path, line numbers, what's wrong, suggested fix, and severity (critical/major/minor)
   > 5. Produce a verdict:
   >    - **APPROVED** — phase output meets quality standards (list what you verified)
   >    - **REJECTED** — list all issues with severity, grouped by file. Include research findings that informed your judgment.
   > 6. Rate overall quality: 1-10 with brief justification
   >
   > Be highly critical. Assume problems exist until you verify otherwise. No rubber-stamping.

3. **If Judge REJECTS:** Attempt to fix the issues:
   - For code-related fixes within scope → apply fixes directly or run `/gsd:execute-phase <N> --gaps-only`
   - Re-submit to Judge (up to **2 revision rounds** per phase)
   - If still rejected after 2 rounds → **INTERRUPT USER** with the Judge's report

4. **If Judge APPROVES:** Log the Judge's quality rating and key findings to STATE.md, then proceed.

The execute-phase workflow also handles:
- Wave-based parallel execution
- Checkpoint auto-approval (via `auto_advance=true` + `_auto_chain_active=true`)
- `human-action` checkpoints → **INTERRUPT USER**, then resume after response

### 4c. Self-Verification
After phase execution AND Judge approval, verify results:

1. Check all SUMMARY.md files for the phase — look for `Self-Check: FAILED`
2. If any failures exist, read the failure details
3. Attempt self-diagnosis:
   - If the fix is code-related and within scope → run `/gsd:execute-phase <N> --gaps-only`
   - If it requires user input → **INTERRUPT USER**
4. If all pass → continue to next phase

### 4d. Update State
```bash
node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" state-set last_completed_phase <N>
```

Re-apply chain flag for next phase:
```bash
node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" config-set workflow._auto_chain_active true
```

## Step 5: Completion

After all phases complete:

1. Run a final self-check across all phase summaries
2. Present completion report:

```
## Autopilot Complete

**Phases executed:** 1 through N
**Status:** [All passed | X issues noted]

### Phase Summary
| Phase | Plans | Status | Judge Rating | Notes |
|-------|-------|--------|-------------|-------|
| 01-setup | 2 | ✅ | 8/10 | — |
| 02-feature | 3 | ✅ | 9/10 | — |
| ... | ... | ... | .../10 | ... |

### Judge Summary
- **Phases approved first pass:** X / N
- **Phases requiring revisions:** X (list which and why)
- **Total issues found:** X (Y critical, Z major, W minor)
- **Key research findings:** [best practices the Judge surfaced that influenced the output]

### Decisions Made Autonomously
- [List key auto-decisions: technology choices, checkpoint approvals, etc.]

### Items for Review
- [Any warnings, skipped verifications, or edge cases]
```

3. Reset autopilot flags:
```bash
node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" config-set workflow._auto_chain_active false
node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" config-set gates.confirm_project true
node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" config-set gates.confirm_phases true
node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" config-set gates.confirm_roadmap true
```
</process>

<interrupt_protocol>
## When to Interrupt the User

**ONLY interrupt when ALL of these are true:**
1. The issue blocks forward progress (can't skip or work around it)
2. Self-diagnosis was attempted and couldn't resolve it
3. The issue is NOT a checkpoint:human-verify or checkpoint:decision (those are auto-approved)

**Types of interrupts:**

### Auth Gate (checkpoint:human-action)
```
## 🔐 Autopilot Paused — Action Required

**Phase:** 03-deployment
**Plan:** 03-02 Configure Auth
**Action needed:** [description from checkpoint]

Reply when done, and autopilot will resume.
```

### Unrecoverable Error
```
## ⚠️ Autopilot Paused — Error

**Phase:** 02-feature
**Plan:** 02-01 API Routes
**Error:** [description]
**Self-diagnosis:** [what was attempted]

Options:
1. Fix and resume → reply "continue"
2. Skip this plan → reply "skip"
3. Stop autopilot → reply "stop"
```

### Verification Failure (after 3 retries)
```
## ⚠️ Autopilot Paused — Verification Failed

**Phase:** 04-integration
**Issue:** [what failed verification]
**Attempts:** 3/3 exhausted

Please review and advise.
```

After ANY interrupt, when the user responds, resume the loop from the current position.
</interrupt_protocol>

<guardrails>
## Safety

- **Never skip `human-action` checkpoints** — these are auth gates that physically require a human
- **Log all autonomous decisions** to STATE.md so the user can review what happened
- **Atomic commits** — each plan still commits independently (GSD executor default)
- **If a phase has 3+ plan failures in execution**, pause and report rather than continuing to dependent phases
- **Destructive operations** (drop tables, delete branches, etc.) still require user confirmation regardless of autopilot mode — this overrides auto-advance for safety
</guardrails>
