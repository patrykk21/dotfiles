---
name: conductor
description: "Ticket-to-PR pipeline for Jira/ClickUp/Linear/GitHub tickets. Auto-detects pilot-shell: when present, delegates plan/implement/verify to /spec or /fix; when absent (or trial expired), falls through to an inline standalone workflow with the same FSM + PR babysit. With no ticket, prompts for a description, routes through /prd (or its standalone equivalent), then /spec."
argument-hint: "<jira-url | clickup-url | linear-url | github-issue-url> | (empty for no-ticket mode)"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Task
  - AskUserQuestion
  - Skill
  - WebFetch
  - WebSearch
  - mcp__claude_ai_Atlassian__*
  - mcp__github-work__*
  - mcp__github-personal__*
  - mcp__convoy-clickup__*
  - mcp__auto-dj-clickup__*
  - mcp__semble__*
  - mcp__playwright__*
---

# /conductor — Ticket-to-PR pipeline (pilot-shell aware, standalone fallback)

Drives a ticket (or free-text intent) from "open" to "PR awaiting review", with two execution paths selected automatically at runtime:

| Path | When | Plan/implement/verify driver |
|---|---|---|
| **Pilot** | `~/.pilot/bin/pilot status` reports `Valid` | pilot-shell `/prd`, `/spec`, `/fix` skills |
| **Standalone** | Pilot missing, trial expired, or no valid license | Inline workflow in this file (no external skill deps) |

Everything else — ticket fetch, state FSM, AGENTS.md self-review, PR creation, CI watch, CodeRabbit handling, reviewDecision branching, screenshot embedding, ticket commenting — is **path-agnostic** and runs the same way in both modes.

If you want GSD's project/milestone orchestration, invoke `/gsd:new-project` directly. `/conductor` no longer wraps GSD.

## Asking questions

Sessions started by `conductor run` or the scheduler launch with `AskUserQuestion` denied, so a choice panel can never stall them. Wherever this command or a skill it calls (`/prd`, `/spec`, `/fix`) would use `AskUserQuestion`, and the tool is unavailable or denied:

1. Run `state needs_input "<the question>"`.
2. Write the question as plain text, with the options numbered and your recommendation first.
3. End your turn. The answer arrives as your next message; run `state working "addressing feedback"` and continue.

In a normal interactive session, `AskUserQuestion` works as usual.

---

## Phase 0 — Detect mode + path

### 0.1 — Detect ticket vs no-ticket mode

Inspect `$ARGUMENTS`:

| Argument shape | Mode |
|---|---|
| Starts with `http://` / `https://` and matches a ticket platform | **Ticket mode** (continue Phase 1) |
| Empty, or free-text without a URL | **No-ticket mode** (jump to Phase 1-NT) |

Ticket platforms detected from URL:

| URL pattern | Platform | Fetch tool |
|---|---|---|
| `*.atlassian.net/browse/*` | Jira | `mcp__claude_ai_Atlassian__*` |
| `app.clickup.com/t/*` | ClickUp | `mcp__convoy-clickup__*` or `mcp__auto-dj-clickup__*` |
| `linear.app/*/issue/*` | Linear | `WebFetch` (best-effort) |
| `github.com/*/issues/*` | GitHub Issue | `mcp__github-work__issue_read` |
| Anything else | Unknown | `WebFetch` (best-effort) |

For Jira, the ticket key is the last path segment (e.g. `PROJ-571` from `.../browse/PROJ-571`).

### 0.2 — Detect pilot availability

Run **once** at the start and stash the result in a shell variable used by Phases 1-NT and 2:

```bash
if command -v pilot >/dev/null 2>&1 \
   && pilot status 2>/dev/null | grep -qE "License Status:[[:space:]]+Valid"; then
  PILOT_OK=1
else
  PILOT_OK=0
fi
```

Treat any of these as `PILOT_OK=0`:

- Binary missing / not on PATH
- `pilot status` exits non-zero
- `pilot status` reports `Expired`, `Invalid`, or anything other than `Valid`
- `pilot status` hangs (use a 5s timeout: `timeout 5 pilot status …`)

Surface the choice to the user once, briefly:

> "Pilot detected — running in pilot mode (`/spec`, `/fix`, `/prd`)." **or**
> "Pilot unavailable (`<reason>`) — running standalone workflow."

Do **not** prompt the user to choose. Detection is deterministic and the standalone path is feature-equivalent for conductor's purposes.

### 0.3 — Load the project guide

A project can keep conductor rules of its own (extra skill-routing rows, a pre-push checklist, its PR base, guardrails) in a guide in the private employer layer. Find the project name, then look for the guide:

```bash
PROJECT_NAME=""
case "$PWD" in
  "$HOME/worktrees/"*) PROJECT_NAME=$(echo "${PWD#$HOME/worktrees/}" | cut -d/ -f1) ;;
esac
[ -z "$PROJECT_NAME" ] && PROJECT_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")
ls "$HOME"/.claude/company/*/conductor/projects/"$PROJECT_NAME".md 2>/dev/null | head -1
```

If a path prints, read that file now and follow it for the whole run. Each of its sections names the phase it extends (1.4, 3, 4.1, 6); where it disagrees with this command, the guide wins. If nothing prints, the project has no guide and this command applies as written.

---

## Phase 1-NT — No-ticket mode (free-text → /prd-or-standalone → plan)

There is no ticket. Capture a clear requirement, then run the plan workflow.

### 1-NT.1 — Capture the requirement

If `$ARGUMENTS` is empty, ask the user once via `AskUserQuestion`:

> What do you want to build? Give me one or two sentences — I'll write a PRD (scope + flows + acceptance criteria) before planning.

If `$ARGUMENTS` already contains a free-text description, use that verbatim — do not re-prompt.

### 1-NT.2 — Branch on path

#### 1-NT.2-P — Pilot path (`PILOT_OK=1`)

Invoke pilot's PRD skill:

```
Skill(skill='prd', args='<the captured description>')
```

`/prd` walks the user through scope/flows/AC, writes `docs/prd/YYYY-MM-DD-<slug>.md`, and hands off automatically to `/spec`. After `/prd` returns control, conductor's role in no-ticket mode is finished — no Jira to transition, no FSM, no PR babysit (no ticket = no scheduler). **STOP after `/prd` completes.**

#### 1-NT.2-S — Standalone path (`PILOT_OK=0`)

Run the inline PRD flow (Section S-PRD below), then the inline plan/implement/verify flow (Section S-SPEC below). After verification, **STOP** — no FSM, no PR babysit (no ticket).

---

## Phase 1 — Ticket mode: validate & route

### 1.1 — Fetch ticket

Use the platform-appropriate MCP / fetch tool from Phase 0.1 to retrieve:

- Title / summary
- Description (full body)
- Acceptance criteria (if any)
- Issue type (Story / Bug / Task / Spike / Epic)
- Status
- Priority
- Affected components / labels
- Comments (additional context the description doesn't carry)

Store the ticket key in a shell variable so later steps can reuse it:

```bash
TICKET_KEY="PROJ-123"   # parsed from URL
TICKET_URL="$ARGUMENTS"
```

### 1.2 — Workability check

Reject before any planning if:

- Status is in a non-workable column (`Done`, `Closed`, `Won't Do`, `Cancelled`)
- Summary is empty / trivial (< ~10 chars of substantive content)
- Title contains explicit blocker language ("Blocked on …" / "Waiting on …" with no resolution)

If rejected, call `state blocked "<reason>"` (see Phase 5), comment on the ticket explaining why, and STOP.

### 1.3 — Auto-route to PRD when AC is weak

Trigger PRD-first when ANY of:

- No Acceptance Criteria section in the description
- AC is a single-line statement under ~50 chars of substantive content
- Issue type is `Spike` or `Epic` (multi-AC, needs scope-pruning)
- Description is mostly screenshots / links with no written intent

**Pilot path:**

```
Skill(skill='prd', args='<TICKET-KEY> <summary> — current AC: <quoted verbatim or "(none)"> — URL: <TICKET_URL>')
```

`/prd` writes `docs/prd/YYYY-MM-DD-<TICKET-KEY>-<slug>.md` and hands off to `/spec`. After `/prd` returns and `/spec` plan is approved, continue to Phase 4 (PR + babysit) — the plan and implementation are already done inside `/spec`.

**Standalone path:** run Section S-PRD below, seeded with the ticket context. After the PRD is written, proceed to Phase 2 (standalone path).

If the user abandons the PRD conversation, call `state failed "PRD abandoned"` and STOP.

### 1.4 — Skill routing (applies to both paths)

Scan the ticket for keywords / paths that call for a particular flow or convention. Both `/spec` and the standalone plan flow read this table; the only difference is who consumes it. The project guide (Phase 0.3) may add rows of its own; apply those too.

| Ticket signal | Action |
|---|---|
| Issue type is **Bug** with a reproducer (steps + expected vs actual) | Pilot: use `/fix`. Standalone: use Section S-FIX (RED test first, ≤150 LOC budget) |
| Issue type is **Spike** with deliverable = research | Treat as research-only — local HTML artifact, no PR (memory `feedback_no_pr_for_research.md`); confirm with user before planning |

If multiple rows match, apply all. Document the choices in the plan so the verifier can audit them.

---

## Phase 2 — Plan + implement + verify

While Phase 2 runs, FSM is `working`. Final state after Phase 2 must be: plan files written, code committed on the worktree branch, tests passing, lint/typecheck green. The PR isn't created yet — that's Phase 4.

### 2-P — Pilot path

**Features (Story / Task / non-trivial Spike):**

```
Skill(skill='spec', args='<TICKET-KEY> <one-line summary> — Ticket: <TICKET-KEY> — URL: <TICKET_URL> — Type: <issue type> — AC: <copied verbatim from ticket>')
```

**Bugs (Issue type = Bug) with a reproducer:**

```
Skill(skill='fix', args='<TICKET-KEY> <one-line summary> — Ticket: <TICKET-KEY> — URL: <TICKET_URL> — Reproducer: <steps> — Expected: <expected> — Actual: <actual>')
```

`/fix` may bail out and tell you to switch to `/spec` if the change exceeds ~150 LOC or turns architectural. Re-invoke as `/spec` with the same ticket context.

While `/spec` / `/fix` runs, the skill writes plan files at `docs/plans/YYYY-MM-DD-<slug>.md`, registers them with `pilot register-plan`, and flips `Status:` from `PENDING` → `COMPLETE` → `VERIFIED`.

When the skill returns:

- Plan `Status: VERIFIED` → continue to Phase 3
- Plan `Status: COMPLETE` (Verify failed) → call `state failed "spec verify exhausted"`, comment on ticket, STOP
- User rejected the plan in the approval gate → call `state failed "plan rejected"`, comment on ticket, STOP

**Do not duplicate `/spec`'s verification.** It already runs lint, typecheck, tests, browser verify, and the reviewer sub-agent. Conductor's job after this phase is PR mechanics.

### 2-S — Standalone path

Use the inline flows in the **Standalone reference** section at the bottom:

| Ticket type | Flow |
|---|---|
| Bug with reproducer, fix ≤ ~150 LOC, no architectural change | Section **S-FIX** |
| Anything else (Story / Task / Spike / Bug needing redesign) | Section **S-SPEC** |

If S-FIX detects scope > 150 LOC or architectural change during implementation, abandon it and restart in S-SPEC with the same ticket context. Don't try to grow S-FIX past its scope.

When the standalone flow returns:

- Plan file marked `Status: VERIFIED` (manually set by the flow) → continue to Phase 3
- Verification failed twice in a row on the same root cause → `state failed "standalone verify exhausted"`, comment on ticket, STOP
- User rejected the plan at the approval gate → `state failed "plan rejected"`, comment on ticket, STOP

---

## Phase 3 — Pre-push self-review against AGENTS.md

**Before EVERY `git push`** — initial PR creation, fix-after-review commits, base-merge commits — re-read the active worktree's `AGENTS.md` and check the diff against every applicable rule. If the project guide (Phase 0.3) has a pre-push checklist, walk that too. Runs the same way in both paths.

```bash
git diff --stat
git diff
```

Walk the checklist:

### 3.1 — Hygiene
- No accidental `console.log` / debug code
- No commented-out code blocks
- No files modified outside the ticket's scope
- No `.planning/` files committed to feature branches (those are local-only)

If any rule fails, **fix it before pushing**. Do not file the violation as "known limitation" in the PR body.

---

## Phase 4 — PR creation & babysit

Identical in both paths.

### 4.1 — Create the PR

Branch convention is the worktree's existing branch, as the launcher created it (memory `feedback_worktree_rename.md`). The PR base is the project's `BASE_BRANCH` from `~/.config/conductor/projects/<project>.env`, unless the project guide names another.

**Draft vs. ready-for-review is per-project** (`PR_DRAFT` in the same file; default `false`). The launcher exports it as `CONDUCTOR_PR_DRAFT`; manual runs read it from the project config. Resolve both, then create the PR with the matching flags:

```bash
PROJECT_NAME=""
case "$PWD" in
  "$HOME/worktrees/"*) PROJECT_NAME=$(echo "${PWD#$HOME/worktrees/}" | cut -d/ -f1) ;;
esac
[ -z "$PROJECT_NAME" ] && PROJECT_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")
PROJ_ENV="$HOME/.config/conductor/projects/${PROJECT_NAME}.env"
proj_setting() { [ -f "$PROJ_ENV" ] && grep -E "^$1=" "$PROJ_ENV" | tail -1 | sed -E "s/^$1=//; s/^\"(.*)\"\$/\1/"; }

# Draft preference: scheduler env var → project .env → default false.
PR_DRAFT="${CONDUCTOR_PR_DRAFT:-$(proj_setting PR_DRAFT)}"
[ "$PR_DRAFT" = "true" ] && DRAFT_FLAG="--draft" || DRAFT_FLAG=""
BASE_BRANCH=$(proj_setting BASE_BRANCH)

gh pr create --base "${BASE_BRANCH:-main}" --fill $DRAFT_FLAG
PR_URL=$(gh pr view --json url --jq .url)
PR_NUM=$(gh pr view --json number --jq .number)
```

When `PR_DRAFT=false` the PR opens **ready-for-review**. When `PR_DRAFT=true` it opens as a **draft** and stays draft (see Phase 4.6).

For **cross-repo PRs** (worktree's git remote points to a repo distinct from where the ticket lives), record the URL-derived host alongside the worktree-derived one — the scheduler needs `gh_pr_url` to reconcile (memory `feedback_conductor_cross_repo_pr.md`).

### 4.2 — Embed screenshots (if the plan flow produced any)

Browser-verify (in `/spec` or in Section S-SPEC's verify step) may emit screenshots. Commit them under `.github/pr-assets/<TICKET-KEY>/` on the PR branch and embed in the PR body using:

```
![alt](https://github.com/{owner}/{repo}/raw/{branch}/.github/pr-assets/{ticket-key}/{file}.png)
```

**Critical:** Use `github.com/.../raw/...`, **NOT** `https://raw.githubusercontent.com/...`. `raw.githubusercontent.com` does not authenticate when GitHub renders PR markdown for private repos, so images appear broken to reviewers even though the asset exists. The `github.com/.../raw/...` URL is a redirect that respects the viewer's GitHub session and works for both public and private repos. Memory: `feedback_screenshot_upload.md`.

After editing the PR body, verify the rendered images load:

```bash
gh pr view "$PR_NUM" --json body --jq .body
```

Open the PR in the browser if any image looks suspicious.

### 4.3 — Report state: awaiting CI

```bash
state awaiting_ci "$PR_URL"
```

### 4.4 — Watch CI

Poll every 30s, cap at ~30 minutes total. Loop until all checks finish:

```bash
DEADLINE=$(( $(date +%s) + 1800 ))
while :; do
  STATES=$(gh pr checks "$PR_NUM" --json state -q '.[].state' 2>/dev/null | sort -u)
  if echo "$STATES" | grep -q "PENDING\|QUEUED\|IN_PROGRESS"; then
    [ "$(date +%s)" -ge "$DEADLINE" ] && { state failed "CI watch timed out after 30 min on $PR_URL"; break; }
    sleep 30
    continue
  fi
  break
done
```

If any check finished `FAILURE` / `ERROR` / `CANCELLED`, treat it as red:

```bash
FAILURES=$(gh pr checks "$PR_NUM" --json name,state -q '[.[] | select(.state == "FAILURE" or .state == "ERROR" or .state == "CANCELLED")] | .[].name')
if [ -n "$FAILURES" ]; then
  state working "fixing CI: $FAILURES"
  # fix, push (Phase 3 self-review first), go back to 4.3
fi
```

### 4.5 — CodeRabbit grace period

**Wait 60 seconds after CI passes** before reading reviews. CodeRabbit marks its CI check as passed before it finishes posting review comments — read too early and you'll miss them.

```bash
sleep 60
gh pr view "$PR_NUM" --json reviews,comments
```

If CodeRabbit (or any reviewer) requested changes, address them:

```bash
state working "addressing review comments"
# fix → Phase 3 self-review → push → back to 4.3 (CI watch + 60s + re-read reviews)
```

### 4.6 — Mark PR ready for review

Respect the project's `PR_DRAFT` setting (resolved in Phase 4.1):

- **`PR_DRAFT=true`**: leave the PR as a **draft**. Do **not** run `gh pr ready` — the project intentionally opens PRs as drafts.
- **`PR_DRAFT=false`**: the PR was already opened ready-for-review, so this is a no-op. Only if a PR was created as a draft for some other reason, mark it ready:

```bash
if [ "$PR_DRAFT" != "true" ]; then
  gh pr ready "$PR_NUM"   # only if the PR is a draft; no-op otherwise
fi
```

### 4.7 — reviewDecision branching

If CI is green and no review changes are requested, query `reviewDecision` **before** deciding the next state — a prior approval may already exist (memory `feedback_check_review_decision.md`):

```bash
DECISION=$(gh pr view "$PR_NUM" --json reviewDecision -q '.reviewDecision' 2>/dev/null)
case "$DECISION" in
  APPROVED)            state approved "$PR_URL" ;;
  CHANGES_REQUESTED)   state working "fixing review comments" ;;   # then fix + push, go to 4.3
  *)                   state awaiting_review "$PR_URL" ;;           # REVIEW_REQUIRED, null, or empty
esac
```

### 4.8 — Comment on the ticket

Add the PR link and a brief summary to the Jira/ClickUp/Linear/GitHub ticket. Use the same MCP that fetched the ticket in Phase 1.1.

Do **not** transition the Jira status yourself — the conductor scheduler handles `In Progress` / `Code Review` transitions based on `conductor.json`. Manual transitions desync the scheduler.

---

## Phase 5 — State FSM

Conductor's launcher exports a `state` shell function that atomically patches the per-worktree `conductor.json` via `worktree-event`. The picker, scheduler, and reconciler all read `conductor.json`. **This is conductor's own infrastructure, not pilot's** — runs identically in both paths.

### 5.1 — Vocabulary (must be exact)

| Call | When |
|---|---|
| `state working "description"` | Actively coding, testing, committing, addressing comments |
| `state awaiting_ci "$PR_URL"` | Created or updated a PR, CI is running |
| `state awaiting_review "$PR_URL"` | CI passed, no prior approval, waiting for human review |
| `state approved "$PR_URL"` | A reviewer approved (set after `reviewDecision == APPROVED`) |
| `state needs_input "question"` | Blocked on a user answer |
| `state blocked "reason"` | Waiting on external dependency (other ticket, team, decision) |
| `state closed "$PR_URL or reason"` | PR closed without merging (terminal) |
| `state failed "reason"` | Cannot complete (terminal) |

Anything outside this vocabulary is rejected by the launcher and silently desyncs the FSM. Memory: `feedback_conductor_state_vocab.md`, `feedback_conductor_state_validation.md`.

### 5.2 — NEVER write to the marker file directly

**🚨 Do NOT do `echo "STATE|PR_URL" > $CONDUCTOR_STATE_MARKER`** or write to `~/.config/conductor/markers/*.state` by hand. Those legacy files are no longer the source of truth — only `state` (or the `worktree-event` fallback below) keeps `conductor.json` and the marker in sync. Memory: `feedback_conductor_slash_state_function.md`.

### 5.3 — Fallback when `state` is not exported

If you invoked `/conductor` outside the conductor launcher (e.g. manually in a regular terminal), `state` may not exist. Shim it:

```bash
if ! type state >/dev/null 2>&1; then
    state() {
        local s="$1"; local d="${2:-}"
        local text="$s"; [ -n "$d" ] && text="$s|$d"
        local ticket; ticket=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        "$HOME/.config/conductor/bin/worktree-event" conductor-state-reported \
            --ticket "$ticket" --text "$text" >/dev/null 2>&1 || true
    }
fi
```

Never fall back to writing the legacy marker.

### 5.4 — Terminal states are write-once

Before transitioning, check whether `conductor.json` already says `merged`, `closed`, `approved`, or `failed`. Those are terminal and set by the scheduler — do NOT overwrite. Re-reporting `working` after `approved` confuses the scheduler.

---

## Phase 6 — Project guardrails (both paths)

If the project guide (Phase 0.3) has a guardrails section, follow every rule in it for the whole run.

---

## Phase 7 — Final report

After a clean run, print:

```
## Conductor complete

Path:   <pilot | standalone>
Ticket: <TICKET-KEY>
PR:     <PR_URL>
State:  <approved | awaiting_review>

Plan:        <path/to/plan.md>
PRD (if any): <path/to/prd.md>
Verify:      ✓ (handled inside /spec or /fix in pilot path; inline S-SPEC verify in standalone)
CI:          ✓
Reviewers:   <reviewDecision value>
```

If the run failed at any phase, the matching `state failed "reason"` or `state blocked "reason"` call is already in place — print the diagnostic and STOP.

---

# Standalone reference (PILOT_OK=0)

The three flows below replace `/prd`, `/spec`, and `/fix` when pilot isn't available. They're deliberately leaner than pilot's skills — they cover what conductor needs (a working ticket-to-PR loop) without the full pilot ceremony (Console UI, plan registration, reviewer sub-agents, browser-verify TS-NNN structure). Quality bar is still: lint green, typecheck green, tests pass, AGENTS.md compliant, browser-verified for UI changes.

## S-PRD — Inline PRD flow

Used by Phases 1-NT.2-S and 1.3 (standalone path).

### S-PRD.1 — Ask scoping questions

Use `AskUserQuestion` once, with up to 4 bundled questions:

1. **Scope:** What's in / out? Name 2-3 things that are NOT this feature.
2. **Primary flow:** Walk me through the happy path as a user (start → end).
3. **Acceptance criteria:** What does "done" look like? List 3-5 testable conditions.
4. **Constraints:** Any non-negotiables — perf, accessibility, browser support, RBAC, existing patterns to follow?

Skip questions for which the captured description (from `$ARGUMENTS` or Phase 1.1) already provides a confident answer. Don't re-ask known facts.

### S-PRD.2 — Write the PRD

Generate a slug from the description (kebab-case, ~3-5 words). Write to:

```
docs/prd/<YYYY-MM-DD>-<TICKET-KEY-or-slug>.md
```

Template:

```markdown
# PRD: <one-line summary>

**Ticket:** <TICKET-KEY or "(no-ticket)">
**URL:** <TICKET_URL or "(none)">
**Date:** <YYYY-MM-DD>
**Path:** standalone

## Problem
<2-3 sentences: what's broken / missing / unclear today>

## Goal
<one sentence: the outcome we want>

## In scope
- <bullet>
- <bullet>

## Out of scope
- <bullet>
- <bullet>

## Primary flow
1. <step>
2. <step>
3. <step>

## Acceptance criteria
- [ ] <testable condition>
- [ ] <testable condition>
- [ ] <testable condition>

## Constraints
- <e.g. RBAC: only `lead` role can access>
- <e.g. perf: TTI under 1s on dashboard page>
- <e.g. patterns: Services → Connectors → Queries>
```

### S-PRD.3 — Hand off

Hand off to S-SPEC with `$PRD_PATH` set. Conductor then runs the standalone plan/implement/verify on top of this PRD.

---

## S-SPEC — Inline plan / implement / verify

Used by Phase 2-S for features (and after S-FIX bails out due to scope).

### S-SPEC.1 — Explore the codebase

Read the targets of the change before planning. Prefer in this order:

1. **CodeGraph** (if `codegraph_context` is available): `codegraph_context(task="<one-line goal>")` for entry points + related symbols.
2. **Semble** (if `mcp__semble__search` or `semble` CLI is available): one query per concept (auth, dashboard, etc.).
3. **Grep / Glob fallback** when neither is available: search for the symbols mentioned in the ticket / PRD.

Read the 3-6 most relevant files in full. Read `AGENTS.md` to confirm architectural rules.

If the change is UI-heavy: also read existing Storybook stories for nearby components to copy the pattern.

### S-SPEC.2 — Write the plan

Slug from the summary (kebab-case). Write to:

```
docs/plans/<YYYY-MM-DD>-<TICKET-KEY-or-slug>.md
```

Template:

```markdown
# Plan: <one-line summary>

**Ticket:** <TICKET-KEY or "(no-ticket)">
**URL:** <TICKET_URL or "(none)">
**PRD:** <PRD_PATH or "(none)">
**Type:** feature
**Path:** standalone
**Status:** PENDING
**Approved:** No
**Worktree:** No
**Date:** <YYYY-MM-DD>

## Goal
<one sentence>

## Approach
<3-5 sentences: high-level strategy, key design decisions, what changes architecturally>

## Files
| File | Change |
|---|---|
| `<path>` | <add | edit | delete> — <one-line reason> |

## Tasks
- [ ] T1 — <discrete step>
- [ ] T2 — <discrete step>
- [ ] T3 — <discrete step>

For each task: state whether a failing test must be written first (default: yes for new behavior or bugfix; no for refactor / docs / config / typings).

## Verification
- [ ] `bun run lint` clean
- [ ] `bun run typecheck` clean
- [ ] `bun run test` — all green (call out specific files exercising the change)
- [ ] Browser-verify (UI changes only): describe the user action that proves the feature works
- [ ] AGENTS.md self-review (Phase 3 of conductor) clean

## Risk / rollback
<1-2 sentences: what could go wrong, how to back out>
```

### S-SPEC.3 — Approval gate

```bash
# Skip approval entirely only if the user has set CONDUCTOR_STANDALONE_AUTO_APPROVE=1
if [ "${CONDUCTOR_STANDALONE_AUTO_APPROVE:-0}" != "1" ]; then
  : # Ask the user
fi
```

Ask via `AskUserQuestion`:

> Plan written to `<plan_path>`. Approve to start implementation, request changes, or reject?

Options:

- **Approve** — set `Approved: Yes` in the plan header, continue
- **Request changes** — capture the feedback (free-text "Other"), revise plan, re-ask
- **Reject** — set `Status: REJECTED`, call `state failed "plan rejected"`, STOP

### S-SPEC.4 — Implement task-by-task

For each task `T<n>` in order:

1. **Set state:** mark T<n> in-progress in the plan and via `TodoWrite` / `TaskCreate`.
2. **RED (if applicable):** write the failing test first. Run it. Confirm it fails for the expected reason (not import error).
3. **GREEN:** write the smallest production code that turns the test green. No extras, no refactor yet.
4. **REFACTOR:** improve quality if obviously needed; tests stay green.
5. **Commit:** small, atomic, message `[<TICKET-KEY>] T<n>: <short description>` (or `[no-ticket] T<n>: …` outside ticket mode).
6. Mark T<n> done in plan and `TodoWrite`.

After all tasks: bump plan `Status: COMPLETE`.

### S-SPEC.5 — Verify

Run in this order, fix any failure before continuing:

```bash
bun run lint
bun run typecheck
bun run test
```

For UI changes, do a **real browser interaction** (not just a unit/snapshot test). Tier priority from `~/.claude/rules/browser-automation.md`:

1. `mcp__claude-in-chrome__*` if loaded
2. `mcp__plugin_chrome-devtools-mcp_*` if loaded
3. `playwright-cli` if installed
4. `agent-browser` if installed

Snapshot → click the primary action → re-snapshot → confirm new state. No click + re-snapshot pair = not verified.

After all checks pass: bump plan `Status: VERIFIED`. Return control to Phase 3 (AGENTS.md self-review) → Phase 4 (PR creation).

If a verify step fails twice in a row on the same root cause, call `state failed "standalone verify exhausted: <root cause>"`, comment on ticket, STOP. Do not loop indefinitely.

---

## S-FIX — Inline bugfix flow

Used by Phase 2-S for bugs with a clear reproducer and scope ≤ ~150 LOC. If during the fix the scope grows past 150 LOC or you discover the bug requires an architectural change (new module, new schema, cross-layer rewiring), **abandon S-FIX and restart in S-SPEC with the same ticket context** — don't try to grow S-FIX past its scope.

### S-FIX.1 — Reproduce with a failing test

Write a test that captures the bug: same inputs, observed-wrong output, expected output. Run it. **Confirm RED** for the right reason (not import error, not flake).

If you cannot reproduce in a test:

- Add a small reproducer script in `scripts/repro-<TICKET-KEY>.ts` that prints expected vs actual, OR
- Switch to S-SPEC and treat it as a feature-level investigation.

### S-FIX.2 — Minimal fix

Single-cause, smallest possible diff. No "while I'm here" cleanups. No refactor of surrounding code. Just the fix.

### S-FIX.3 — Verify GREEN

Run:

```bash
bun run lint
bun run typecheck
bun run test
```

The reproducer test must go GREEN, and no other test may regress.

### S-FIX.4 — Defense-in-depth (if applicable)

If the bug is data-shape or validation related, add validation at the layer it slipped past (entry, business logic, environment guard) so the same class of bug can't recur silently. One layer of validation per layer the data crosses — see `~/.claude/rules/development-practices.md` § Defense-in-Depth.

### S-FIX.5 — Plan stub for the FSM and PR body

S-FIX produces no detailed plan up front, but the FSM and PR body still want a file. Write:

```
docs/plans/<YYYY-MM-DD>-<TICKET-KEY-or-slug>.md
```

with:

```markdown
# Fix: <one-line summary>

**Ticket:** <TICKET-KEY>
**URL:** <TICKET_URL>
**Type:** bugfix
**Path:** standalone
**Status:** VERIFIED

## Bug
<observed behavior>

## Root cause
<one-paragraph diagnosis pointing at the specific file:line>

## Fix
<one paragraph: what changed, why this is the minimal correct change>

## Reproducer test
`<test file>:<test name>` — was RED before the fix, GREEN after.

## Defense-in-depth
<if applicable: which layer got new validation>
```

Then proceed to Phase 3 (self-review) → Phase 4 (PR).

---

## Notes on degradation

The standalone path deliberately omits a few things pilot ships:

- **No spec-review / changes-review sub-agent.** Conductor's Phase 3 self-review against `AGENTS.md` is the quality gate. Read the diff, walk the checklist, fix violations before push.
- **No Console UI / `pilot register-plan`.** Plans are plain markdown in `docs/plans/`; conductor's FSM is in `conductor.json` driven by the `state` function. Nothing else needs to know about the plan.
- **No `PILOT_BRANCH_ISOLATION_ENABLED` / worktree management.** You're already in a worktree (the launcher created it). Standalone doesn't create new branches mid-flow.
- **No TS-NNN structured browser-verify scenarios.** The verify step still does a real browser interaction — it's just described inline in the plan instead of in a separate scenarios file.

If you find yourself wanting those features for a specific ticket, install pilot for that ticket. The detection in Phase 0.2 will pick it up automatically next run.

ARGUMENTS: $ARGUMENTS
