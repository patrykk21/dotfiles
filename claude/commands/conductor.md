---
name: conductor
description: "Ticket-to-PR pipeline for Jira/ClickUp/Linear/GitHub tickets. Delegates plan/implement/verify to pilot-shell /spec (or /fix for bugs). With no ticket, prompts for a description, routes through /prd, then /spec. Owns echelon bookends: ticket fetch, conductor state FSM, PR creation, CI watch, CodeRabbit handling, AGENTS.md self-review."
argument-hint: "<jira-url | clickup-url | linear-url | github-issue-url> | (empty for no-ticket mode)"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
  - Skill
  - WebFetch
  - WebSearch
  - mcp__claude_ai_Atlassian__*
  - mcp__github-work__*
  - mcp__github-personal__*
  - mcp__convoy-clickup__*
  - mcp__auto-dj-clickup__*
---

# /conductor — Ticket-to-PR pipeline (pilot-shell native)

Slim wrapper over pilot-shell's `/spec`, `/fix`, and `/prd`. Owns the echelon-specific bookends: ticket fetch, `state` FSM updates, PR creation with private-repo-safe screenshot URLs, CI watch with CodeRabbit handling, and AGENTS.md self-review before every push.

**What this command does NOT reimplement:**

| Removed | Replaced by |
|---|---|
| Direct implementation in Path A | `/spec` (planning + TDD + verification) |
| GSD chain (Path B / new-project / new-milestone / resume) | `/spec` for features; `/fix` for bugs |
| Custom plan/review/test phases | `/spec` Plan → Implement → Verify; `/fix` RED → fix → verify |
| Custom worktree handling | `/spec` Branch Strategy (`PILOT_BRANCH_ISOLATION_ENABLED`) |
| Plan registration | `pilot register-plan` (auto-invoked inside `/spec`) |
| Custom auto-route when AC weak | Built-in `/prd` (auto-invoked in Phase 1.1, hands off to `/spec`) |

If you want GSD's project/milestone orchestration, invoke `/gsd:new-project` directly. `/conductor` no longer wraps GSD.

---

## Phase 0 — Detect mode

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

For Jira, the ticket key is the last path segment (e.g. `ECH-571` from `.../browse/ECH-571`). For echelon, expect `ECH-XXX` keys.

---

## Phase 1-NT — No-ticket mode (free-text → /prd → /spec)

There is no ticket. The goal is to capture a clear product requirement, then run the full spec workflow.

### 1-NT.1 — Capture the requirement

If `$ARGUMENTS` is empty, ask the user once:

> What do you want to build? Give me one or two sentences — I'll route it through `/prd` to flesh out scope, flows, and acceptance criteria before planning.

If `$ARGUMENTS` already contains a free-text description, use that verbatim — do not re-prompt.

### 1-NT.2 — Hand off to `/prd`

Invoke pilot-shell's PRD skill with the description as the argument. `/prd` will:

1. Walk the user through scope, flows, and acceptance criteria (Q&A gated by `PILOT_PLAN_QUESTIONS_ENABLED`)
2. Write `docs/prd/YYYY-MM-DD-<slug>.md`
3. Hand off automatically to `/spec` via `Skill('spec', args='<summary> — PRD: docs/prd/...md — see PRD')`

```
Skill(skill='prd', args='<the captured description>')
```

After `/prd` completes, `/spec` takes over (plan → approve → implement → verify). Conductor's role in no-ticket mode is finished — there is no Jira to transition, no `state` FSM, no PR babysit phase (no ticket = no scheduler). The user drives the PR themselves once `/spec` finishes verification.

**STOP after `/prd` hands off.** Do not proceed to Phase 2 or below.

---

## Phase 1 — Ticket mode: validate & route

### 1.1 — Fetch ticket

Use the platform-appropriate MCP / fetch tool from the table in Phase 0 to retrieve:

- Title / summary
- Description (full body)
- Acceptance criteria (if any)
- Issue type (Story / Bug / Task / Spike / Epic)
- Status
- Priority
- Affected components / labels (if known)
- Comments (for additional context the description doesn't carry)

Store the ticket key in a shell variable so later steps can reuse it:

```bash
TICKET_KEY="ECH-XXX"  # parsed from URL
TICKET_URL="$ARGUMENTS"
```

### 1.2 — Workability check

Reject before any planning if:

- Status is in a non-workable column (`Done`, `Closed`, `Won't Do`, `Cancelled`)
- Summary is empty / trivial (under ~10 chars of substantive content)
- Title contains explicit blocker language ("Blocked on …" / "Waiting on …" with no resolution)

If rejected, report `state blocked "<reason>"` (see Phase 5 — State FSM), comment on the ticket explaining why, and STOP.

### 1.3 — Auto-route to `/prd` when AC is weak

Trigger `/prd` first when ANY of:

- No Acceptance Criteria section in the description
- AC is a single-line statement under ~50 chars of substantive content
- Issue type is `Spike` or `Epic` (multi-AC, needs scope-pruning)
- Description is mostly screenshots / links with no written intent

```
Skill(skill='prd', args='<TICKET-KEY> <summary> — current AC: <quoted verbatim or "(none)"> — URL: <TICKET_URL>')
```

`/prd` writes `docs/prd/YYYY-MM-DD-<TICKET-KEY>-<slug>.md` and hands off to `/spec`. After `/prd` returns and `/spec` plan is approved, continue to Phase 4 (PR + babysit). The plan and implementation are already done inside `/spec`.

If the user abandons the `/prd` conversation, call `state failed "PRD abandoned"` and STOP.

### 1.4 — Skill routing (echelon)

Before invoking `/spec` (or `/fix`), scan the ticket for keywords / paths that imply specialised echelon skills the agent should pull in. The universal pilot-shell rules + this repo's `AGENTS.md` are always implied; this table is the conditional layer.

| Ticket signal | Action |
|---|---|
| Issue type is **Bug** with a reproducer (steps + expected vs actual) | Use `/fix` instead of `/spec` — pilot-shell's RED-test-first bugfix lane is the right fit |
| Description mentions schema / migration / `drizzle` / new column | Plan must respect the Drizzle journal `when`-monotonicity rule (see `AGENTS.md` and memory `feedback_drizzle_journal_when.md`); never run SQL manually |
| Description mentions new Server Action / data fetching | Reaffirm in plan: Server Actions over API routes; `createRequestCache` / `createDbCache`, never raw `cache()`; GET for fetching, POST for mutations |
| Description mentions analytics / feature flag | Use `posthog` MCP and enum-typed flag names per `AGENTS.md § Feature Flags` |
| Description mentions UI changes / new component | Include Storybook stories with `play` function test (`AGENTS.md § Storybook Stories`) |
| Description touches `/lib/api/services/**` | Plan must thread requests through Services → Connectors → Queries (never service-to-query) |
| Issue type is **Spike** with deliverable = research | Treat as research-only — local HTML artifact, no PR (memory `feedback_no_pr_for_research.md`); confirm with user before planning |

If multiple rows match, apply all. Document the choices in the plan's reasoning so the verifier can audit them.

---

## Phase 2 — Plan + implement + verify (via `/spec` or `/fix`)

Compose a seeded prompt and hand off. `/spec` (or `/fix`) owns plan → approve → implement → verify.

**For features (Story / Task / non-trivial Spike):**

```
Skill(skill='spec', args='<TICKET-KEY> <one-line summary> — Ticket: <TICKET-KEY> — URL: <TICKET_URL> — Type: <issue type> — AC: <copied verbatim from ticket>')
```

**For bugs (Issue type = Bug) with a reproducer:**

```
Skill(skill='fix', args='<TICKET-KEY> <one-line summary> — Ticket: <TICKET-KEY> — URL: <TICKET_URL> — Reproducer: <steps> — Expected: <expected> — Actual: <actual>')
```

`/fix` may itself bail out and tell you to switch to `/spec` if the change exceeds ~150 LOC or turns architectural. Follow its escalation — re-invoke as `/spec` with the same ticket context.

While `/spec` / `/fix` is running, conductor's state is `working`. The skill writes plan files at `docs/plans/YYYY-MM-DD-<slug>.md`, registers them with `pilot register-plan`, and flips `Status:` from `PENDING` → `COMPLETE` → `VERIFIED` as it progresses.

When the skill returns:

- Plan `Status: VERIFIED` → continue to Phase 3
- Plan `Status: COMPLETE` (Verify failed) → call `state failed "spec verify exhausted"`, comment on ticket, STOP
- User rejected the plan in the approval gate → call `state failed "plan rejected"`, comment on ticket, STOP

**Do not duplicate `/spec`'s verification.** It already runs lint, typecheck, tests, browser verify, and the reviewer sub-agent. Conductor's job after this phase is PR mechanics, not re-running checks.

---

## Phase 3 — Pre-push self-review against AGENTS.md

**Before EVERY `git push`** — initial PR creation, fix-after-review commits, base-merge commits, all of them — re-read `/Users/vigenerr/Work/Groupon/echelon/AGENTS.md` (or whichever worktree's AGENTS.md is active) and check the diff against every applicable rule.

```bash
git diff --stat
git diff
```

Then walk the checklist:

### 3.1 — Layered architecture (CRITICAL)
- Services in `/lib/api/services/**` import from `connectors/**` only; **never** from `queries/**`
- Connectors wrap results in `ServerActionResult<T>`
- Queries call Drizzle and may use `createDbCache` / `createRequestCache` — never raw React `cache()`

### 3.2 — Code standards
- No `any` types
- No JSDoc comments (TypeScript types are sufficient)
- No `@deprecated` markers — dead code is deleted, not annotated
- No `AbortSignal` / `signal` parameters
- No dynamic imports (`await import()`) inside Server Actions
- Naming: PascalCase components, camelCase functions, kebab-case filenames

### 3.3 — Data fetching
- Server Actions for fetching, not API routes — unless external access is required
- REST verbs respected (GET fetches, POST creates, PUT updates, DELETE removes, PATCH partial-updates)
- No "POST for fetching" anti-pattern

### 3.4 — Database migrations
- Schema changes → `bun run db:generate` then `bun run db:migrate`; never manual SQL
- Data-only migrations get a journal entry with a `when` strictly greater than the previous entry's `when` (memory `feedback_drizzle_journal_when.md` — silent skip otherwise)

### 3.5 — Hygiene
- No accidental `console.log` / debug code
- No commented-out code blocks
- No files modified outside the ticket's scope
- No `.planning/` files committed to feature branches (those are local-only)
- Changelog `/CHANGELOG.md` updated if the change is user-facing (see `AGENTS.md § Changelog Guidelines` — frontend `apps/frontend/package.json` bumped, not the monorepo root)

If any rule fails, **fix it before pushing**. Do not file the violation as "known limitation" in the PR body.

---

## Phase 4 — PR creation & babysit

### 4.1 — Create the PR

Branch convention is the worktree's existing branch (the launcher created it from `main-do` with the `ECH-{ticket}-{slug}` naming convention — see memory `feedback_worktree_rename.md`). The base branch is always `main-do`.

```bash
gh pr create --base main-do --draft --fill
PR_URL=$(gh pr view --json url --jq .url)
PR_NUM=$(gh pr view --json number --jq .number)
```

For **cross-repo PRs** (when the worktree's git remote points to a repo distinct from where the ticket lives), record the URL-derived host alongside the worktree-derived one — the scheduler needs `gh_pr_url` to reconcile (memory `feedback_conductor_cross_repo_pr.md`).

### 4.2 — Embed screenshots (if `/spec` produced any)

`/spec`'s browser-verify step may emit screenshots. Commit them under `.github/pr-assets/<TICKET-KEY>/` on the PR branch and embed in the PR body using:

```
![alt](https://github.com/{owner}/{repo}/raw/{branch}/.github/pr-assets/{ticket-key}/{file}.png)
```

**Critical:** Use `github.com/.../raw/...`, **NOT** `https://raw.githubusercontent.com/...`. Echelon is a private repo; `raw.githubusercontent.com` does not authenticate when GitHub renders PR markdown for private repos, so images appear broken to reviewers even though the asset exists. The `github.com/.../raw/...` URL is a redirect that respects the viewer's GitHub session and works for both public and private repos. Memory: `feedback_screenshot_upload.md`.

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
  # fix, push, go back to 4.3
fi
```

### 4.5 — CodeRabbit grace period

**Wait 60 seconds after CI passes** before reading reviews. CodeRabbit marks its CI check as passed before it finishes posting review comments — read too early and you'll miss them. (Origin: existing conductor behavior; preserved here.)

```bash
sleep 60
gh pr view "$PR_NUM" --json reviews,comments
```

If CodeRabbit (or any reviewer) requested changes, address them:

```bash
state working "addressing review comments"
# fix → push → back to 4.3 (CI watch + 60s + re-read reviews)
```

### 4.6 — reviewDecision branching

If CI is green and no review changes are requested, query `reviewDecision` **before** deciding the next state — a prior approval may already exist (memory `feedback_check_review_decision.md`):

```bash
DECISION=$(gh pr view "$PR_NUM" --json reviewDecision -q '.reviewDecision' 2>/dev/null)
case "$DECISION" in
  APPROVED)            state approved "$PR_URL" ;;
  CHANGES_REQUESTED)   state working "fixing review comments" ;;  # then fix + push, go to 4.3
  *)                   state awaiting_review "$PR_URL" ;;          # REVIEW_REQUIRED, null, or empty
esac
```

### 4.7 — Comment on the ticket

Add the PR link and a brief summary to the Jira/ClickUp/Linear/GitHub ticket. Use the same MCP that fetched the ticket in Phase 1.1.

Do **not** transition the Jira status yourself — the conductor scheduler handles `In Progress` / `Code Review` transitions based on `conductor.json`. Manual transitions desync the scheduler.

---

## Phase 5 — State FSM

Conductor's launcher exports a `state` shell function that atomically patches the per-worktree `conductor.json` via `worktree-event`. The picker, scheduler, and reconciler all read `conductor.json`.

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

## Phase 6 — Echelon-specific guardrails

| Rule | Why |
|---|---|
| Base branch is `main-do`, not `main` | Echelon's main branch is `main-do` (see `CLAUDE.local.md`) |
| Worktrees: `ECH-{ticket}-{short-description}`, never random names | Memory `feedback_worktree_rename.md` |
| Do NOT start `bun run dev` | The server is always running on port 3000 (per `CLAUDE.local.md`) |
| Use `bun run <script>` from `apps/frontend/package.json`, not raw `bunx` | Per `CLAUDE.local.md` |
| Tempo time logging only for `ECH-` / `MTG-` / `MBNXT-` tickets — never for conductor worktree codes (`869d27pz*` etc.) | Memory `feedback_tempo_ech_only.md` |
| Don't commit `.planning/` to feature branches | Local working files only — `AGENTS.md § Protected Paths` |
| Don't modify files outside the ticket's scope | Echelon convention; reviewer rejects on sight |

---

## Phase 7 — Final report

After a clean run, print:

```
## Conductor complete

Ticket: <TICKET-KEY>
PR:     <PR_URL>
State:  <approved | awaiting_review>

Plan:        <path/to/plan.md>
PRD (if any): <path/to/prd.md>
Verify:      ✓ (handled inside /spec or /fix)
CI:          ✓
Reviewers:   <reviewDecision value>
```

If the run failed at any phase, the matching `state failed "reason"` or `state blocked "reason"` call is already in place — just print the diagnostic and STOP.
