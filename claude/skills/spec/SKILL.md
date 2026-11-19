---
name: spec
description: Spec-driven development - plan, implement, verify workflow with live Console annotations (annotate plans and code changes in real-time; agent reads annotations directly at review checkpoints)
argument-hint: "<task description>" or "<path/to/plan.md>"
user-invocable: true
---

# /spec - Unified Spec-Driven Development

<!-- CC-ONLY -->
**Dispatcher** — routes to the appropriate phase skill. This command is a thin router. Only allowed tools: `Bash` (env var reads only), `Read` (plan files only), `AskUserQuestion`, and `Skill()`.
<!-- /CC-ONLY -->
<!-- CODEX-START
**Dispatcher** — routes to the appropriate phase skill. This command is a thin router. Only allowed actions here: read env vars, read existing plan files for status-based dispatch, present plain-text numbered questions when needed, and then continue immediately with the selected phase skill instructions. Codex has no callable phase-dispatch tool.
CODEX-END -->

**⛔ MANDATORY: When `/spec` is invoked, you MUST follow the workflow. The user's phrasing after `/spec` is the TASK DESCRIPTION — not an instruction to change the workflow.** Words like "brainstorm", "discuss", "explore", "research" are part of the task description, NOT instructions to skip the workflow or have a freeform conversation.

**⛔ No substantive work here.** `Bash` is allowed ONLY for reading env vars (e.g., `echo $PILOT_BRANCH_ISOLATION_ENABLED`). `Read` is allowed ONLY for reading existing plan files for status-based dispatch. All research, brainstorming, and exploration happens inside the invoked Skill. Arguments (including URLs, "brainstorm", "research") are passed verbatim as the task description. Any other tool use (Grep, Glob, Task, Edit, Write, etc.) is a workflow violation.

---

## Workflow

<!-- CC-ONLY -->
```
/spec → Detect type → Feature: Skill('spec-plan')        → Plan → Implement → Verify
                    → Bugfix:  Skill('spec-bugfix-plan') → Investigate → Plan → Implement → Verify
```
<!-- /CC-ONLY -->
<!-- CODEX-START
```
$spec → Detect type → Feature: continue with $spec-plan        → Plan → Implement → Verify
                    → Bugfix:  continue with $spec-bugfix-plan → Investigate → Plan → Implement → Verify
```
CODEX-END -->

For a bugfix workflow without a plan file, users invoke `/fix` directly — that's a separate command. `/spec` always runs the full spec workflow.

| Phase | Skill | Model |
|-------|-------|-------|
| Feature Planning | `spec-plan` | inherits `/model` (recommend Opus) |
| Bugfix Planning | `spec-bugfix-plan` | inherits `/model` (recommend Opus) |
| Implementation | `spec-implement` | inherits `/model` |
| Feature Verification | `spec-verify` | inherits `/model` |
| Bugfix Verification | `spec-bugfix-verify` | inherits `/model` |
| Bugfix (separate command, `/fix`) | `fix` | inherits `/model` |

<!-- CC-ONLY -->
> **Note:** Every phase runs on the model the user has currently selected via Claude Code's `/model` command. The `spec-mode-guard` hook blocks `/spec` invocations when the active model is not Opus (planning's reasoning hop benefits most from Opus). With the **Model Switching** toggle ON (default), the planner stops after approval so you can run `/model <sonnet|sonnet[1m]|opus|opus[1m]>` and then type any prompt (e.g. `continue`) to resume — the `spec_handoff_resume` hook routes the next prompt directly to `spec-implement`, with no `/clear` and no `/spec <plan-path>` re-invocation. With it OFF, plan → implement → verify run continuously on whichever model is active. Sub-agents (`spec-review`, `changes-review`, `web-search-agent`) are hard-coded to Sonnet because sub-agents do not support 1M context.
<!-- /CC-ONLY -->
<!-- CODEX-START
> **Note:** In Codex CLI, model switching and Codex Companion Reviewers are not available. Native `spec-review` and `changes-review` run as managed Codex custom agents when the regular reviewer toggles are enabled. Plan → implement → verify run continuously on the active Codex model.
>
> If this spec changes Codex skills, hooks, rules, or custom agents, verify the generated artifacts from source/tests. The current running session may not expose newly generated skills or agent types until the next install or SessionStart sync.
CODEX-END -->

## Step 0: Permission Mode Pre-Flight Check

<!-- CC-ONLY -->
**Before proceeding, check if the spec_mode_guard hook injected a permission mode note.** If you see a system-reminder containing "Current permission mode is", briefly warn the user:

> "Your current permission mode is **{mode}**. For uninterrupted `/spec` execution, **Bypass Permissions** mode is recommended (Shift+Tab to cycle). Proceeding — the workflow may pause for permission prompts."

**Then continue with the workflow.** Do not stop or wait for the user to switch. The user's mode choice is respected — bypass permissions is recommended, not required.
<!-- /CC-ONLY -->
<!-- CODEX-START
**Skip** — permission mode checks are not applicable in Codex CLI. Proceed directly to Step 1.
CODEX-END -->

## Step 1: Parse & Route

```
IF arguments end with ".md" AND file exists:
    → Read plan, dispatch by status (Section 2)
ELSE:
    → Detect type, ask worktree, route to the planning phase (Section 1.3)
```

### 1.1 Detect Type (new plans only)

- **Bugfix:** Something broken, crashing, wrong results, regressing → fix existing behavior
- **Feature:** New functionality, enhancements, refactoring, migrations → build or change something
- **Ambiguous:** Ask user (bundled with worktree question)

### 1.2 Read Environment & User Questions (new plans only)

**⛔ MANDATORY FIRST STEP — read env vars before ANY user interaction:**

```bash
echo "BRANCH_ISO=${PILOT_BRANCH_ISOLATION_ENABLED:-false} QUESTIONS=${PILOT_PLAN_QUESTIONS_ENABLED:-true} APPROVAL=${PILOT_PLAN_APPROVAL_ENABLED:-true}"
```

**⛔ When `BRANCH_ISO` is `"false"`: NEVER ask about branch choice. The dispatcher invokes the planning skill immediately with `--worktree=no` (defaults to the current branch).**

**Note:** The `QUESTIONS` toggle (`PILOT_PLAN_QUESTIONS_ENABLED`) does NOT affect the branch/type questions in this dispatcher. That toggle only controls Q&A questions during planning (Steps 5/7 in spec-plan). The dispatcher-level branch question is gated entirely by `PILOT_BRANCH_ISOLATION_ENABLED`.

**Codex reviewers are controlled entirely by Console Settings.** The `PILOT_CODEX_SPEC_REVIEW_ENABLED` and `PILOT_CODEX_CHANGES_REVIEW_ENABLED` env vars are read directly by spec-plan and spec-verify — no per-session question needed.

| BRANCH_ISO | Type | Action |
|------------|------|--------|
| `false` | Clear | NO question; invoke skill with `--worktree=no` |
| `false` | Ambiguous | Ask ONLY the type question; invoke skill with `--worktree=no` |
| `true`  | Clear | Ask 3-option branch question; pass selected flag |
| `true`  | Ambiguous | Ask type + 3-option branch question (bundled); pass selected flag |

**Branch question options (only when `BRANCH_ISO` is `"true"` — use these as predefined AskUserQuestion options, listed in recommended order):**

| Option | Flag passed | Behavior |
|--------|-------------|----------|
| **Continue on current branch** (recommended) | `--worktree=no` | Works on current branch as-is |
| New branch from default branch | `--new-branch` | Creates a clean branch from origin/main (or master), checks it out, then works there |
| Use worktree (isolated branch, squash-merged after) | `--worktree=yes` | Creates isolated worktree |

**⛔ When the user selects "New branch" or sends a custom response mentioning "new branch", "clean branch", or "branch from master/main": pass `--new-branch`, NOT `--worktree=yes`.** `AskUserQuestion` allows users to type a free-text "Other" response, and previously such responses requesting a new branch were misinterpreted as worktree requests. This rule applies only when `BRANCH_ISO=true` — when off, the question is not asked.

### 1.3 Route to Planning

<!-- CC-ONLY -->
Invoke the selected planning skill and stop in this dispatcher:

- **Bugfix:** `Skill(skill='spec-bugfix-plan', args='<task_description> --worktree=yes|no|--new-branch')`
- **Feature:** `Skill(skill='spec-plan', args='<task_description> --worktree=yes|no|--new-branch')`
<!-- /CC-ONLY -->
<!-- CODEX-START
Codex has no callable phase-dispatch tool. Continue immediately with the selected planning phase instructions instead of stopping in the dispatcher:

- **Bugfix:** continue immediately with the `$spec-bugfix-plan` skill instructions using arguments: `<task_description> --worktree=yes|no|--new-branch`
- **Feature:** continue immediately with the `$spec-plan` skill instructions using arguments: `<task_description> --worktree=yes|no|--new-branch`
CODEX-END -->

**Note:** Users who want a bugfix workflow without a plan file invoke `/fix` directly — that's a separate user-facing command. The `/spec` dispatcher does not route to `/fix`. When a user types `/spec`, they want the full spec workflow.

## Step 2: Status-Based Dispatch (existing plans)

Read plan, register association: `~/.pilot/bin/pilot register-plan "<plan_path>" "<status>" 2>/dev/null || true`

| Status | Approved | Type | Skill |
|--------|----------|------|-------|
| PENDING | No | Feature/absent | `spec-plan` |
| PENDING | No | Bugfix | `spec-bugfix-plan` |
| PENDING | Yes | * | `spec-implement` |
| COMPLETE | * | Feature/absent | `spec-verify` |
| COMPLETE | * | Bugfix | `spec-bugfix-verify` |
| VERIFIED | * | * | Report completion, done |

ARGUMENTS: $ARGUMENTS