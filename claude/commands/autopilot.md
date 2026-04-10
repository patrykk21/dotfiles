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

For **Jira**: use Atlassian MCP tools (extract ticket key from URL, e.g. `ECH-571` from `.../browse/ECH-571`)
For **ClickUp**: use WebFetch to read the ticket
For **GitHub Issues**: use GitHub MCP tools
For **other platforms**: use WebFetch, parse what you can

### Step 2: Implement the ticket
Work autonomously to implement it end-to-end:

1. **Read project conventions** — AGENTS.md / CLAUDE.md in the project root
2. **Plan** — identify files to change, break into tasks if needed
3. **Implement** — write code following project conventions
4. **Verify** — run the project's test, lint, typecheck commands. Fix any errors.
5. **Commit & push** — format: `[TICKET-KEY] Description`. Push to current branch.
6. **Create PR** — against the project's base branch with a descriptive summary. If `$AUTOPILOT_PR_ASSIGNEE` is set, assign the PR to that user (e.g., `gh pr create --assignee "$AUTOPILOT_PR_ASSIGNEE"`)
7. **Comment on ticket** — add the PR link and brief summary back on the original ticket (use the platform's MCP tools if available)
8. **Transition ticket** — move the ticket to "Code Review" / "In Review" / "Review" status. For Jira: get available transitions, find the one matching review, and transition. For other platforms: update status if the MCP tools support it.

### Step 3: Signal completion
If the environment variables are set (they are when launched by the autopilot scheduler):
```bash
[ -n "$AUTOPILOT_COMPLETION_MARKER" ] && echo "PR_URL" > "$AUTOPILOT_COMPLETION_MARKER"
```
On failure:
```bash
[ -n "$AUTOPILOT_FAILURE_MARKER" ] && echo "reason" > "$AUTOPILOT_FAILURE_MARKER"
```

### Signaling when you need input
If you need to ask the user a question, write the question to the waiting marker BEFORE asking:
```bash
[ -n "$AUTOPILOT_WAITING_MARKER" ] && echo "Brief question summary" > "$AUTOPILOT_WAITING_MARKER"
```
After the user responds, clear it:
```bash
[ -n "$AUTOPILOT_WAITING_MARKER" ] && rm -f "$AUTOPILOT_WAITING_MARKER"
```
This lets `autopilot status` show which sessions need attention.

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
