---
name: spec-plan
description: "Spec planning phase - explore codebase, design plan, get approval"
argument-hint: "<task description> or <path/to/plan.md>"
user-invocable: false
model: opus[1m]
hooks:
  Stop:
    - command: uv run --no-project python "${CLAUDE_PLUGIN_ROOT}/hooks/spec_plan_validator.py"
---

# /spec-plan - Planning Phase

**Phase 1 of the /spec workflow.** Explores codebase, designs implementation plan, verifies it, gets user approval.

**Input:** Task description (new) or plan path (continue unapproved)
**Output:** Approved plan at `docs/plans/YYYY-MM-DD-<slug>.md`
**Next:** On approval → `Skill(skill='spec-implement', args='<plan-path>')`

---

## ⛔ Critical Constraints

- **NO sub-agents during planning** except Step 10 (spec-review, when enabled in settings)
- **Run spec-review when enabled** — it runs for every feature spec when `$PILOT_SPEC_REVIEW_ENABLED` is not `"false"`. Context level is NOT a valid reason to skip. To disable, use Console Settings → Reviewers → Spec Review toggle.
- **NEVER write code during planning** — planning and implementation are separate phases
- **NEVER assume — verify by reading files**
- **ONLY stopping point is plan approval** — everything else is automatic. Never ask "Should I fix these?"
- **Re-read plan after user edits** — before asking for approval again
- **Plan file is source of truth** — survives across auto-compaction cycles
- **Quality over speed** — never rush due to context pressure

## Step 0: Setup & Question Policy

### 0.1 Read Toggle Configuration

**⛔ Run FIRST, before any other step.** Read all toggle env vars in a single Bash call:

```bash
echo "QUESTIONS=$PILOT_PLAN_QUESTIONS_ENABLED REVIEWER=$PILOT_SPEC_REVIEW_ENABLED CODEX_SPEC=$PILOT_CODEX_SPEC_REVIEW_ENABLED APPROVAL=$PILOT_PLAN_APPROVAL_ENABLED"
```

Reference these values throughout: Steps 4/6 (questions), 10 (reviewer + Codex — Codex controlled by Console Settings), and 12 (approval).

### 0.2 Asking User Questions

**⛔ If `PILOT_PLAN_QUESTIONS_ENABLED` is `"false"` (above),** skip ALL `AskUserQuestion` calls in Steps 4 and 6. Make reasonable default choices (including selecting the recommended approach in Step 6) and document them in the plan under an "Autonomous Decisions" sub-section. Continue to the next step immediately.

**⛔ ALWAYS use the `AskUserQuestion` tool** (when questions are enabled) — never list numbered questions in plain text. Each question gets its own entry with predefined options users can select. This provides a structured form UI that is much easier to answer than freeform numbered lists.

**⛔ Default is to ASK, not skip.** Every plan benefits from at least one round of user alignment. Only skip questions when the task is a single-file change with zero ambiguity.

**Questions batched into max 2 interactions:** Batch 1 (before exploration) clarifies task/scope/priorities. Batch 2 (after exploration) covers approach selection and design decisions. **Both batches are expected for most tasks** — skipping both is the exception, not the norm.

**Principles:** Present options with trade-offs (not open-ended). Start open, narrow down. Challenge vagueness — make abstract concrete. 1-2 focused questions beat 4 vague ones. Questions clarify HOW to implement, not whether to expand scope.

## Step 1: Special Cases (conditional — skip both sub-sections if neither applies)

This step handles the two situational planning paths. Most new plans skip both — when the request is a brand-new feature and no existing code is being replaced, proceed directly to Step 2 (Create Header).

### 1a. Extending an Existing Plan

When adding tasks to an existing plan: load it, parse structure, verify compatibility, mark new tasks with `[NEW]`, update totals. If original + new > 12 tasks, suggest splitting.

### 1b. Migration/Refactoring — Feature Inventory

**When replacing existing code, complete a Feature Inventory BEFORE creating tasks:**

1. List ALL files being replaced with their functions/classes
2. Map EVERY function to a task — no row may be "Not mapped"
3. Every row needs a Task # or explicit "Out of Scope" with user confirmation

"Out of Scope: Changes to X" = X migrates AS-IS (still needs migration task). "Out of Scope: Feature X" = X intentionally REMOVED (needs user confirmation, no task needed).

## Step 2: Create Plan File Header (FIRST)

1. **Parse flags** from arguments: `--worktree=yes|no` or `--new-branch` (default: `Yes`). Strip the flag from task description.

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
   BRANCH_NAME="feat/<plan_slug>"
   # If branch already exists, append short timestamp
   if git rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1; then
     BRANCH_NAME="feat/<plan_slug>-$(date +%m%d-%H%M)"
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

   `<plan_slug>` is derived from the task description (same slug used for the plan filename). If checkout fails even after stashing (e.g. no origin remote), warn the user and fall back to current branch — the stash is restored automatically. After branch creation, continue with `Worktree: No` semantics (work directly on the new branch). Note: the stash remains in `git stash list` and can be recovered with `git stash pop` if needed.

2b. **Create worktree early (if `--worktree=yes`):**

   ```bash
   ~/.pilot/bin/pilot worktree detect --json <plan_slug>
   # If not found:
   ~/.pilot/bin/pilot worktree create --json <plan_slug>
   # Returns: {"path": "...", "branch": "spec/<slug>", "base_branch": "main"}
   ```

   All file writes use the worktree path as base. If creation fails (old git): continue without worktree, set to `No`.

3. **Generate filename:** (for both worktree and new-branch paths) `docs/plans/YYYY-MM-DD-<feature-slug>.md` — slug from first 3-4 words (lowercase, hyphens). If worktree active, use worktree path as base directory.

4. **Fetch author email** (best-effort, do not fail if unavailable):

   ```bash
   ~/.pilot/bin/pilot status --json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('email',''))" 2>/dev/null
   ```

   If the command returns a non-empty email, include `Author: <email>` in the header. If empty or fails, omit the Author line entirely.

5. **Write initial header:**

   ```markdown
   # [Feature Name] Implementation Plan

   Created: [Date]
   Author: [email if available]
   Status: PENDING
   Approved: No
   Iterations: 0
   Worktree: [Yes|No]
   Type: Feature

   > Planning in progress...

   ## Summary

   **Goal:** [Task description from user]

   ---

   _Exploring codebase and gathering requirements..._
   ```

6. **Register plan:** `~/.pilot/bin/pilot register-plan "<plan_path>" "PENDING" 2>/dev/null || true`

**Do this FIRST** — before any exploration or questions. Status bar shows progress immediately.

## Step 3: Workspace Scan (MANDATORY, BEFORE QUESTIONS)

**Why this step exists.** Batch 1 clarifying questions (Step 4) are generated *before* exploration. Without code context, options collapse to generic shapes ("extend existing" vs "new module") instead of grounded ones ("Extend `LicenseAuth` in `launcher/auth.py:42`"). A single ~2-second scan up front fixes that — and the same scan is reused in Step 5 so we never pay for `codegraph_context` twice.

**⛔ Always runs**, regardless of `PILOT_PLAN_QUESTIONS_ENABLED`. Autonomous mode benefits *more* from grounded defaults, not less — when there is no user to disambiguate, the codebase has to.

### 3.1: Run the scan

1. **CodeGraph orientation** (always):

   ```
   codegraph_context(task="<task description from user>")
   ```

   Returns entry points, related symbols, and key code locations.

2. **Semble pattern search** (skip if `codegraph_context` already returned ≥3 highly relevant hits AND the task has no clear noun targets — keep total budget under ~2s):

   ```
   mcp__semble__search(query="<2-3 key nouns from task>")
   ```

   Use natural-language intent for conceptual tasks ("how does auth work"); use identifier-like queries when the task names a symbol ("LicenseAuth save_pretrained"). One call, top-k default.

### 3.2: Capture structured output (in-context, NOT in the plan file yet)

Record the scan results in this shape so Steps 3, 4, and 5 can all consume them:

```
Workspace Scan
- Entry points: [file:line, file:line, ...]
- Related symbols: [Name @ file:line, ...]
- Similar patterns: [Semble hit @ file:line — 1-line summary, ...]
- Greenfield?: [yes | no]
```

`Greenfield?: yes` ⇔ both CodeGraph and Semble returned no relevant hits for this task. Set this explicitly — Steps 4 and 6 use it to decide whether to ground options in real code or fall back to generic options.

### 3.3: Hand-off to downstream steps

- **Step 4 (Batch 1 questions)** consumes the scan output and grounds every option label in real files/symbols when they exist. If `Greenfield?: yes`, falls back to generic options and documents the fallback under "Autonomous Decisions".
- **Step 5 (Exploration)** skips 5.1's `codegraph_context` re-run — that work happened here. It proceeds directly to deeper exploration (`codegraph_explore`, `codegraph_search`, dependency analysis).
- **Step 6 (Batch 2 questions)** applies the same labeling discipline to approach and design options.

**Do NOT write scan output into the plan file at this step** — the plan file is composed in Step 9. The scan output is working context for the planning phase.

## Step 4: Task Understanding, Discuss & Clarify

1. Restate the task in your own words — core problem, assumptions
2. **Scope check:** Does this task describe multiple independent subsystems (e.g., "build chat, file storage, billing, and analytics")? If so, flag immediately — don't spend questions refining details of a task that needs decomposition first. Suggest splitting into separate plans, one per subsystem, each producing working software on its own. Proceed with the first sub-task.
3. Identify gray areas:

   | Domain      | Typical Gray Areas                                 |
   | ----------- | -------------------------------------------------- |
   | UI/frontend | Layout, interaction patterns, empty/loading states |
   | API/backend | Response shape, error codes, auth, pagination      |
   | CLI/scripts | Output format, flags, exit codes                   |
   | Data/config | Schema, migration, validation, defaults            |

4. **⛔ Code-first rule: ground every question in the Step 3 Workspace Scan output.** Before formulating a question, ask "can I answer this from the codebase?" If yes, do that instead — don't ask. For questions you do ask, **option labels must reference real files and symbols when the scan found them** — e.g., `Extend LicenseAuth in launcher/auth.py:42`, not `Extend existing module`. Only ask the user about decisions the code can't make — purpose, priority trade-offs, scope boundaries, behavioral expectations not yet encoded.

   - If `Greenfield?: yes` in the scan output, fall back to generic options and note the fallback under "Autonomous Decisions" in Step 9.
   - If the scan output names symbols/files relevant to a question, generic labels are a regression — use the names. Asking the user about facts already in the codebase, or asking with abstract options when grounded ones are available, is the single biggest source of unnecessary friction in planning.

5. **Ask Batch 1 questions** → notify, then use `AskUserQuestion` with each question as a separate entry with predefined options:

   ```bash
   ~/.pilot/bin/pilot notify plan_approval "Input Needed" "<plan_name> — clarification questions" --plan-path "<plan_path>" 2>/dev/null || true
   ```

   Each question must have 2-4 concrete options. Use `multiSelect: true` when choices aren't mutually exclusive.

   Even when the task seems clear, ask about: scope boundaries (what's explicitly out), priority trade-offs (speed vs completeness), or behavioral expectations (error handling, edge cases). **Only skip if the task is a trivial single-file change.**

## Step 5: Exploration

**⛔ START FROM THE STEP 3 WORKSPACE SCAN — do NOT re-run `codegraph_context` with the same query.**

#### 5.1: Review Step 3 scan output

The Workspace Scan in Step 3 already ran `codegraph_context(task=<task description>)` and (when applicable) a Semble pattern search. Re-read its structured output before any deeper exploration:

```
Entry points: [...]
Related symbols: [...]
Similar patterns: [...]
Greenfield?: [yes | no]
```

If `Greenfield?: yes` AND the task is conceptual rather than symbol-mapped, **now** is the time to broaden with `mcp__semble__search` using different phrasings — Step 3 only ran the obvious noun query. Otherwise, proceed to 5.2 with the scan results as your starting set of entry points.

#### 5.2: Deep dive with CodeGraph explore

After orienting, use `codegraph_search` to find specific symbol names, then:

```
codegraph_explore(query="SymbolA SymbolB relevant-file.ts")
```

This returns **full source code sections** from all relevant files in ONE call — replacing dozens of Read/Grep calls. Use specific symbol names (from search results), not natural language. Follow the call budget in the tool description.

#### 5.3: Systematic exploration

**Explore one area at a time (sequentially, not parallel).** Use CodeGraph and Semble as primary tools — Grep/Glob only for exact text patterns.

| Need                            | Tool                                                    |
| ------------------------------- | ------------------------------------------------------- |
| **Orient on the task**          | CodeGraph `codegraph_context(task=<description>)` — already done in Step 3 |
| **Deep understanding of code**  | CodeGraph `codegraph_search` → `codegraph_explore(query="<symbol names>")` |
| **Understand a feature by intent** | Semble `semble search "how does X work"` or `mcp__semble__search` |
| **Find symbols by name**        | CodeGraph `codegraph_search`                            |
| **Discover similar code from a hit** | Semble `semble find-related file.ts 42` or `mcp__semble__find_related` |
| **Extract enclosing block at `file:line`** | `Read` with `offset`/`limit`, or `codegraph_node` (by symbol name) |
| **Project file structure**      | CodeGraph `codegraph_files`                             |
| **Call tracing**                | CodeGraph `codegraph_callers`/`codegraph_callees`       |
| **Library/framework docs**      | Context7                                                |
| **Real-world GitHub examples**  | grep-mcp                                                |
| **Exact text/regex**            | Grep/Glob (last resort)                                 |

**Areas (in order):** Architecture → Similar Features → Dependencies → Tests

#### 5.4: Dependency analysis (MANDATORY for 3+ file changes)

For every function you plan to modify: (1) `codegraph_callers` + `codegraph_callees` for the call graph, (2) `Grep` for the symbol name to catch callers the graph may miss, (3) `codegraph_impact` to assess blast radius. CodeGraph gives structure; Grep gives completeness — use both.

For each area: document hypotheses, note full file paths, track unanswered questions. After exploration: read identified files to verify hypotheses, build complete mental model, identify integration points, note reusable patterns.

## Step 6: Approach Selection & Design Decisions

**⛔ Do NOT skip this step.** After exploration, always weigh competing approaches before committing. Even when one approach seems obvious, considering alternatives validates the choice and surfaces blind spots.

**Two parts — both mandatory in-process; the plan only records the chosen path:**

#### Part A: Overall Approach

Internally consider 2-3 implementation approaches based on exploration findings. For each candidate, evaluate:

- **Name** — short label, **referencing real symbols/files from the Step 3 Workspace Scan when available** (e.g., "Extend `OrderHandler` in `src/handlers/order.py`" vs "New `OrderService` module under `src/services/`"). Generic labels ("Extend existing handler") are a regression — only use them when `Greenfield?: yes` in the scan output.
- **How it works** — 2-3 sentences
- **Trade-offs** — frame as **"X at the cost of Y"** — never recommend without stating what it costs
- **Recommendation** — pick a preferred approach with reasoning

If exploration also revealed scope ambiguity (gaps, optional features, multiple directions), include scope items as part of this step. `AskUserQuestion(multiSelect: true)` for scope items; unselected items go to "Out of Scope" or "Deferred Ideas."

#### Part B: Design Decisions

Within the chosen approach, resolve remaining design choices. Each decision gets 2-3 concrete options with trade-offs and your recommendation.

**Notify, then ask (Batch 2):**

```bash
~/.pilot/bin/pilot notify plan_approval "Design Decisions" "<plan_name> — architecture choices" --plan-path "<plan_path>" 2>/dev/null || true
```

Use `AskUserQuestion` — Part A (approach selection) and Part B (design decisions) can be combined into a single Batch 2 interaction when the decisions are related.

**When questions are disabled (`PILOT_PLAN_QUESTIONS_ENABLED=false`):** Still evaluate approaches and design decisions internally. Select the recommended approach, resolve design decisions with reasonable defaults, and document all choices with reasoning in the plan's "Autonomous Decisions" section.

**What ends up in the plan (`## Approach` section, Step 9):** only the chosen approach's **Name** and **Why** (1-2 sentences capturing what it gives us and what it costs). Do NOT list rejected alternatives in the plan — they're decision exhaust, not implementer information. The only exception: if a user-rejected option is one an implementer might re-derive ("why aren't we just doing X?"), capture that rejection as a single sentence inside the `Why:` line.

Incorporate choices into plan design, proceed to Step 7.

## Step 7: Implementation Planning

### 7.0: File Structure (when 4+ tasks expected, otherwise inline per task)

When the plan will have 4+ tasks, write a `## File Structure` section before tasks listing every file with one-line responsibility — decomposition decisions get locked in here. For 1–3 task plans skip this; the per-task `Files:` block already gives the same view.

```markdown
## File Structure

- `src/foo/bar.ts` (create) — pure function: `parseFoo(input) → Foo`. No I/O.
- `src/foo/loader.ts` (create) — fetches and caches Foo from API. Wraps `parseFoo`.
- `tests/foo/bar.test.ts` (create) — unit tests for `parseFoo`.
```

One responsibility per file. Files that change together live together. In existing codebases, follow established patterns — don't restructure unrelated code.

### 7.1: Task Granularity

**Task Granularity:** Each task: independently testable, focused (2-4 files max), verifiable. Split if multiple unrelated DoD criteria; merge if one can't be tested without the other. Don't create tasks for setup/boilerplate with no standalone value — fold into the first task that uses them. Task ORDER implies dependencies — no separate `Dependencies:` field needed.

**Task Structure (3 required fields — keep it tight):**

```markdown
### Task N: [Component Name — make the TITLE the objective. "Rename foo → bar in launcher" tells the reader everything; do not then write a 2-sentence Objective restating it.]

**Objective:** [OPTIONAL — include ONLY when the title cannot convey purpose. If the title is self-explanatory ("Rename X → Y", "Add /api/users endpoint", "Migrate v10 → v11"), OMIT this field entirely. When included, ≤2 sentences capturing why or cross-task implications the title can't. If covered by a specific E2E scenario, reference it inline: "verified by TS-002".]

**Files:**

- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py`
- Test: `tests/exact/path/to/test.py`

**Key Decisions / Notes:**

- [Technical approach, pattern to follow with file:line ref]
- `Trivial:` [Include this bullet ONLY for trivial changes — one-line justification: "≤ 5 net new lines, no new branch/loop/try with non-trivial body, no new public symbol, no new error path; covered by `<existing-test-or-verify-command>`". Otherwise omit entirely.]

**Definition of Done:**

- [ ] [Verifiable behavioral criterion — e.g., "GET /api/users?role=admin returns only admin users"]
- [ ] [Additional verifiable criterion if the task has multiple observable outcomes]
- [ ] Verify: `uv run pytest tests/path/to/test.py -q` (and any other command that proves the criteria above)
```

**Rules:**

- **DoD must be verifiable.** ✅ "GET /api/users?role=admin returns only admin users" ❌ "Feature works correctly".
- **Tests-pass and no-diagnostics are implicit** — every task must end with those. Do NOT add them as DoD bullets; only list task-specific behaviors.
- **The last DoD bullet IS the verify command.** No separate `Verify:` block.
- **`Trivial:` is a per-task annotation, not a section** — the reviewer agent and `spec-verify` Step 2.1 audit it against the diff regardless of where it sits, as long as it's the literal token `Trivial:` somewhere in the task body.
- **Key Decisions: aim for ≤5 bullets per task.** Prefer `file:line` refs over prose. Multi-paragraph explanations belong in a comment in the code, not in the plan — the plan should point the implementer at WHERE to look and WHAT pattern to follow, not re-explain the existing system.

#### Test plan parsimony

**Testing posture preference.** If there is no project-level testing rule/memory and this plan would introduce several test classes or force a choice between unit-only vs unit+functional coverage, ask one concise question about testing posture. Default to the parsimonious posture here if questions are disabled or the user does not specify a preference.

When listing files for a task, do not auto-create a new `tests/.../test_<file>.py` line for every modified production file. Apply these rules in order:

1. If an existing test class for this production class already exists, reuse it (modify, do not duplicate).
2. If the change is genuinely trivial (≤ 5 net new lines, no new branch/loop/try with non-trivial body, no new public symbol, no new error path), set the task's `Trivial:` field with the justification and the existing covering test/verification command — and omit the test file from `Files:`.
3. Otherwise, plan **at most 1 new unit test class + at most 1 new functional/integration test class** for this production class. More than that requires an explicit `Why >2 test classes:` note in `Key Decisions`.
4. Never plan a test file per method or per branch. The test class is the unit; methods inside it cover branches.

The reviewer agent (`pilot/agents/changes-review.md`) and `spec-verify` Step 2 audit these rules against the actual diff — they are not advisory.

**Performance considerations:** When a task processes data on a hot path (render loops, request handlers, polling callbacks), note it in Key Decisions. Flag: expensive computations that should be cached/memoized, heavy dependencies that have lighter alternatives, and repeated work that can be avoided when input hasn't changed.

**Zero-context assumption:** Assume implementer knows nothing. Provide exact file paths, explain domain concepts, reference similar patterns.

**Assumptions (conditional):** Only write a `## Assumptions` section when an assumption — if wrong — would silently invalidate a task. One bullet per real assumption: what you assume + which task numbers depend on it. Omit the section when there are none; do NOT include tautological assumptions ("config.json is the authoritative store") just to fill space.

#### Step 7.2: Goal Verification Criteria (skip step if no cross-task observable outcomes exist)

After creating tasks, ask: **is there a user-facing observable outcome that NO single E2E scenario captures AND NO single task DoD captures?** If no → skip this step entirely; the `## Goal Verification` section does not appear in the plan. spec-verify Step 10 audits via E2E and task-DoD source keys in that case.

If yes → write **at most 3 truths** for the `## Goal Verification > ### Truths` section. Each truth must be cross-task and not reducible to a single TS-NNN or task DoD reference. If you find yourself writing `[behavior] — TS-NNN passes`, that's not a truth — it's a redirect; delete it and rely on TS-NNN itself.

Do NOT list "supporting artifacts" — they duplicate the per-task `Files:` blocks. Do NOT paraphrase task titles as truths — the task list is the in-scope inventory.

#### Step 7.3: Completeness Probe

**⛔ Skip this step when task count ≤ 2** AND the plan does NOT touch security, authentication, data integrity, or destructive operations — the probe's ~2-min cost exceeds its value for 1–2 task changes whose error paths the implementer can audit by inspection. For 3+ task plans, OR any plan touching sensitive surfaces regardless of size, run the probe in full.

Before locking the truth list, work backward from the success state to find missing observable behaviors. For the chosen approach, walk these four prompts once:

1. **What could prevent the success state?** For each prerequisite the success path assumes, is there a truth covering what the system does when the prerequisite fails (missing input, invalid input, conflicting state, expired credential, rate-limit exceeded, downstream dependency unavailable, concurrent modification)?
2. **What are the cancellation / abort paths?** If the user can initiate the success path, can they cancel mid-flight? Is the observable state after cancel specified?
3. **What are the boundary inputs?** Empty, zero, negative, max length, unicode, whitespace-only, duplicate, exactly-at-limit.
4. **What are the concurrency edges?** If two callers exercise the path simultaneously, is the observable outcome specified, or is implicit serialization being assumed?

For each gap found, either add a truth covering it OR add an explicit `Out of Scope` entry under `## Scope`. Silence is the bug; explicit out-of-scope is the fix. Don't manufacture coverage — if a path is genuinely impossible in this codebase, say so in `## Assumptions` with the supporting finding.

This probe replaces ad-hoc "did I think of everything?" with a checklist. Cost: ~2 minutes of planning. Value: catches the unspecified error paths that are the single largest source of "passes test but breaks on edge case" bugs.

## Step 8: E2E Test Scenarios (Conditional)

**Skip when:** Runtime profile would be Minimal (no UI, no server, no user-facing entry points). Use the same classification logic as `spec-verify` Step 0 (Runtime classification sub-section) — if Phase B would be skipped entirely, skip this step too.

For features with UI or user-facing workflows, create structured E2E scenarios describing exactly how a user verifies the feature works. These become the verification contract for Phase B in `spec-verify` — the verifier executes them step by step rather than improvising.

**Format — add as `## E2E Test Scenarios` section in the plan:**

```markdown
### TS-001: [Scenario Name]
**Priority:** Critical | High | Medium
**Preconditions:** [Required state — e.g., "logged in as admin", "no existing items"]
**Mapped Tasks:** Task 1, Task 3

| Step | Action | Expected Result |
|------|--------|-----------------|
| 1 | [Navigate / click / fill — concrete browser automation action] | [What user sees] |
| 2 | [Next action] | [Expected UI response] |
```

**Guidelines:**
- 3–8 scenarios typical — focus on user-visible workflows, not unit-level behavior
- **Critical** = must pass before deployment; **High** = essential UX; **Medium** = edge cases / error states
- Every task that changes UI or user-visible behavior must be covered by at least one scenario
- Steps must be executable via browser automation — Claude Code Chrome, playwright-cli, or agent-browser (concrete: navigate, click, fill, read page — no "observe manually")
- Test what users see, not internal implementation — same observable inputs and outputs

When scenarios are written, update Goal Verification truths to reference them (e.g., "TS-001 passes end-to-end").

## Step 9: Write Full Plan

**Save to:** `docs/plans/YYYY-MM-DD-<feature-name>.md`

**Parsimony rule:** every section below is either **required** or **conditional**. Conditional sections MUST be omitted entirely when they have nothing concrete to say — empty headings are noise. The reader should be able to skim the plan in under a minute.

**Dedup principle — each fact lives in ONE section:**

- **File paths and per-file changes** → `## Implementation Tasks` (per-task `Files:` block). Never in Summary, Approach, or anywhere else.
- **What gets built** → `## Implementation Tasks`. The task list IS the in-scope work — DO NOT add a separate "In Scope" bullet list that paraphrases task titles.
- **What does NOT get built** → `## Out of Scope`. Explicit boundary decisions a reasonable reader might assume.
- **Observable user-facing outcomes after the plan lands** → `## Goal Verification > ### Truths`.
- **Per-task acceptance criteria** → task `Definition of Done` (not duplicated as a Goal Verification truth).
- **Domain context an implementer can't infer from code** → `## Context for Implementer` (optional). Per-file gotchas go in that task's `Key Decisions`, not here.

If you find yourself writing the same fact in two places, delete one — the longer/more-specific version stays.

**Required sections:** Summary · Approach · Progress Tracking · Implementation Tasks.
**Conditional sections** (include only when applicable, omit entirely otherwise): Out of Scope · Context for Implementer · Runtime Environment · Feature Inventory · Assumptions · Risks and Mitigations · Goal Verification · E2E Test Scenarios · Open Questions · Deferred Ideas.

```markdown
# [Feature Name] Implementation Plan

Created: [Date]
Status: PENDING
Approved: No
Iterations: 0
Worktree: [Yes|No]
Type: Feature

## Summary

**Goal:** [One sentence — what the user can do / observe after this lands.]

## Out of Scope (only when there is an explicit boundary decision a reasonable reader might assume is included; otherwise omit the whole section)

- [Items a reasonable reader might assume are included but aren't. Skip CYA "don't edit build artifacts" bullets — those are obvious. If you can't name a real boundary decision, omit the section.]

## Approach

**Chosen:** [Short name referencing real symbols/files from the workspace scan.]
**Why:** [1-2 sentences — what it gives us and what it costs.]

## Context for Implementer (only when there is a non-obvious cross-task constraint that two or more tasks need to respect, AND it does not fit in any single task's `Key Decisions`; otherwise omit)

[One short paragraph — cross-task domain context an implementer can't infer from the code. If you find yourself listing per-file patterns or gotchas, move them to the relevant task's `Key Decisions` instead.]

## Runtime Environment (only if project has a running service AND `spec-verify` / `spec-implement` will need it)

- **Start command / Port / Health check / Restart procedure**

## Feature Inventory (only for migration/refactoring — see Migration section)

## Assumptions (only when an assumption, if wrong, would silently invalidate a task — link to the dependent task numbers)

- [What you assume] — Task N depends on this

## Risks and Mitigations (conditional — only when there's a Medium-or-higher real risk worth a mitigation commitment; omit entirely on plans where the answer is "be careful")

| Risk | Likelihood | Impact | Mitigation |

⚠️ Real risks only — drop hedges ("be careful when splitting files", "follow conventions"). Mitigations must be commitments verification can check.
✅ "Reset to null when project not in list" ❌ "Handle edge cases"

## Goal Verification (only when there is a cross-task observable outcome that NO single E2E scenario and NO single task DoD captures; otherwise omit the whole section — spec-verify Step 10 audits via E2E + task DoD source keys when this is absent)

> Skip-test: if every truth you would write reduces to `TS-NNN passes` or `Task N DoD verifies`, drop the section. Pure-reference truths are noise.

### Truths

> **Cap: 3 truths.** Each must be a cross-task user-perspective outcome that cannot be checked by reading one E2E scenario or one task's DoD. If you can't write a truth that isn't a paraphrase of an existing E2E/DoD, the section doesn't belong.

1. [Cross-task observable outcome — falsifiable, user-perspective]

## E2E Test Scenarios (only when there is a UI / server / user-facing entry point AND at least one task changes it — see Step 8)

[Scenarios from Step 8. Internal logic verifications belong in task DoD, not here.]

## Progress Tracking

- [ ] Task 1: [one-line summary]
- [ ] Task 2: [one-line summary]

> Source of truth for completion. `spec-implement` toggles `[ ]` → `[x]` here. Keep short — full task bodies live below.

## Implementation Tasks

[Tasks from Step 7 — full per-task bodies.]

## Open Questions (only if any remain unresolved at approval time)

## Deferred Ideas (only if any surfaced and the user wants them captured)
```

## Step 10: Plan Verification

### 10.0: No-Placeholders Self-Check (always — before launching reviewers)

⛔ Walk the plan file once, fresh-eyed, and grep for the patterns below. **Every match is a plan failure** — fix inline before sending the plan to a reviewer or asking for approval.

**Forbidden placeholder patterns:**

- `TBD`, `TODO`, `FIXME`, "implement later", "fill in details", "details below"
- "add appropriate error handling", "add validation", "handle edge cases" — without specifying which cases
- "write tests for the above" — tasks must specify the actual test cases, not a meta-instruction
- "similar to Task N" — implementers may read tasks out of order; repeat the relevant content
- Steps that describe *what* to do without showing *how* (code blocks required for code steps)
- References to types, functions, methods, files, or env vars not defined in any task
- Bracketed angle-brackets like `<your-code-here>`, `<insert-X>` outside of header literal placeholders
- Goal Verification truths that are not falsifiable ("works correctly", "is fast enough")

```bash
# Quick grep (run in worktree or repo root):
grep -nEi "TBD|TODO|FIXME|implement later|fill in details|appropriate error handling|similar to Task" "<plan_path>"
```

If anything matches, fix it inline (no new round-trip needed). Then proceed to spec-review launch below.

---

**⛔ If `PILOT_SPEC_REVIEW_ENABLED` is `"false"` (from Step 0),** skip the Claude reviewer launch below and proceed straight to the Codex section.

**⛔ Auto-skip the Claude reviewer for small plans.** If the plan has **task count ≤ 2** AND it does NOT touch security, authentication, data integrity, or destructive operations, skip the Claude reviewer launch — reviewer overhead exceeds value for a change the implementer can audit by inspection. Continue to the Codex section below; Codex still runs **only** when the user has explicitly opted in via `PILOT_CODEX_SPEC_REVIEW_ENABLED`.

For 3+ task plans, OR any plan touching sensitive surfaces regardless of task count, run the Claude reviewer below in full.

**When running:** Run spec-review for every applicable feature spec. Missing edge cases and unclear DoD criteria are size-independent once the plan crosses the size gate.

```bash
SESS_ID=$(echo $PILOT_SESSION_ID)
```

**Derive plan slug** from the plan filename: strip the date prefix (`YYYY-MM-DD-`) and `.md` extension. Example: `2026-03-02-sku-builder-modal-cleanup.md` → `sku-builder-modal-cleanup`.

Output path: `~/.pilot/sessions/<SESS_ID>/findings-spec-review-<plan-slug>.json`

**⛔ Delete stale findings before launching** (previous run of the same plan may have left a file):

```bash
rm -f "$OUTPUT_PATH"
```

```
Task(
  subagent_type="pilot:spec-review",
  run_in_background=true,
  prompt="""
  **Plan file:** <plan-path>
  **User request:** <original task description>
  **Clarifications:** <any Q&A>
  **Output path:** <absolute path to findings JSON>

  Review for alignment with requirements AND adversarial risks.
  Write findings JSON to output_path using Write tool.
  IMPORTANT: Include the plan file path in your output JSON as the "plan_file" field.
  """
)
```

**⛔ NEVER use `TaskOutput`** to retrieve results — it dumps the full agent transcript into context, wasting thousands of tokens.

#### Codex Adversarial Review (Optional — launch immediately after Claude reviewer)

**If `PILOT_CODEX_SPEC_REVIEW_ENABLED` is `"true"` (from Step 0):**

Launch Codex review NOW — it runs in parallel with the Claude reviewer above.

**⛔ Codex-once rule.** Codex runs at most once per `/spec` invocation. Before launching, check the sentinel file. If it exists, the review already ran in this session — skip the launch and the collection sub-step below. Plan iterations (annotation feedback, plan edits, fixing prior findings) do NOT trigger another Codex run.

```bash
SESS_ID="${PILOT_SESSION_ID:-default}"
CODEX_FLAG="$HOME/.pilot/sessions/$SESS_ID/codex-spec-review-ran-<plan-slug>.flag"
if [ -f "$CODEX_FLAG" ]; then
  echo "Codex already reviewed this plan in this session — skipping (codex-once)."
  # Skip the launch and the Codex collection sub-step. Continue with Claude reviewer results only.
fi
```

**⛔ DO NOT use `adversarial-review --base` or `adversarial-review --scope branch` for plans.** Those subcommands bundle a git diff and feed it to Codex as the review target. Plan files in `pilot-shell` are gitignored (see `.gitignore` line ~271 — `docs/plans` is excluded), so the bundled diff is empty, and Codex returns a meta-finding ("no implementation diff was provided") with zero substantive findings on the actual plan content. Use the `task` subcommand with `--prompt-file` instead — it lets Codex Read the plan file directly via its own tools, with no diff dependency. (The `adversarial-review` path remains correct for `spec-verify`, where there is real working-tree code to scan.)

1. Detect companion path and project root:
```bash
CODEX_COMPANION=$(ls ~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs 2>/dev/null | sort -V | tail -1)
PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-$(pwd)}"
```

2. Build the review prompt file by rendering the **template at `${CLAUDE_PLUGIN_ROOT}/agents/spec-review-codex.md`**. The template is the single source of truth for plan-review semantics — do NOT re-state the prompt inline in this skill. Substitute three placeholders:
   - `{{PLAN_PATH}}` — absolute path to the plan file
   - `{{PLAN_GOAL}}` — the 1–2 sentence Goal sentence from the plan's `## Summary`
   - `{{CONTEXT_FILES}}` — newline-separated absolute paths to source/reference files the plan ports from or extends (use the files referenced in `## Context for Implementer`)

```bash
PROMPT_TEMPLATE="${CLAUDE_PLUGIN_ROOT}/agents/spec-review-codex.md"
PROMPT_FILE="/tmp/codex-spec-review-${PILOT_SESSION_ID:-default}-<plan-slug>.md"

# Set these before rendering:
PLAN_PATH="/absolute/path/to/docs/plans/YYYY-MM-DD-<slug>.md"
PLAN_GOAL="<one or two sentences from the plan Summary>"
# CONTEXT_FILES is a newline-separated list — use printf to build it:
CONTEXT_FILES=$(printf -- '- %s\n' \
  /absolute/path/to/source-or-pattern-file-1 \
  /absolute/path/to/source-or-pattern-file-2)

PLAN_PATH="$PLAN_PATH" PLAN_GOAL="$PLAN_GOAL" CONTEXT_FILES="$CONTEXT_FILES" \
PROMPT_TEMPLATE="$PROMPT_TEMPLATE" PROMPT_FILE="$PROMPT_FILE" \
uv run --no-project python -c '
import os, pathlib
text = pathlib.Path(os.environ["PROMPT_TEMPLATE"]).read_text()
for key in ("PLAN_PATH", "PLAN_GOAL", "CONTEXT_FILES"):
    text = text.replace("{{" + key + "}}", os.environ[key])
pathlib.Path(os.environ["PROMPT_FILE"]).write_text(text)
'
```

3. Launch the task in background. **⛔ For `task`, the companion's `--background` flag IS supported (unlike `review`/`adversarial-review` where only Claude Code's `Bash(run_in_background=true)` detaches).** Use the companion's own background mode here — the launch command returns the job ID immediately on stdout. Capture the job ID for collection.

   ```
   Bash(
     command="cd $PROJECT_ROOT && node $CODEX_COMPANION task --background --prompt-file \"$PROMPT_FILE\"",
     run_in_background=false,
     timeout=60000
   )
   ```

   The stdout looks like: `Codex Task started in the background as task-<id>. Check /codex:status task-<id> for progress.` Extract the `task-…` token and store as `JOB_ID`.

**Do NOT wait** — proceed to collect the Claude reviewer results first.

#### Collect Review Results

**Wait for Claude reviewer results (bash polling — NOT Read loop):**

```bash
OUTPUT_PATH="<findings-path>"
for i in $(seq 1 150); do [ -f "$OUTPUT_PATH" ] && echo "READY" && break; sleep 2; done
```

Then Read the file once. If not READY after 5 min, re-launch synchronously.

**⛔ Validate findings:** After reading the JSON, verify that the `plan_file` field matches the current plan path. If it doesn't match, the findings are stale from a previous `/spec` — delete the file, re-launch the reviewer, and wait again.

**Fix Claude reviewer findings immediately** — must_fix → should_fix. Suggestions if reasonable.

#### Collect Codex Results (if launched)

**⛔ MANDATORY — NEVER skip or defer the Codex review.** If Codex was launched above, you MUST collect and act on its results before proceeding. The Codex review runs as `Bash(run_in_background=true)` — you will be automatically notified when it completes.

**⛔ The completion notification is the ONLY valid signal.** Do NOT read the output file to check if the review is done. The file may contain partial output from an in-progress review — reading it before the notification arrives leads to false conclusions ("no findings" when the review is still running). This is the #1 cause of premature Codex skip.

**⛔ If the notification hasn't arrived yet:** Do NOT proceed to Step 11 or approval. Do NOT read the output file. Do NOT conclude the review failed. Wait for the `<task-notification>` with `<status>completed</status>`. If you are tempted to check the file — that is the exact mistake this rule prevents.

**⛔ "Wait" does NOT mean "end your turn."** Ending the conversation turn lets the user think the workflow is finished and triggers a stop hook that pulls you out. Do not output a closing text message ("Waiting for codex…", "Holding for completion…"), do not call `ScheduleWakeup` as a substitute for staying engaged. Stay in-turn until the `<task-notification>` arrives. While waiting, do something productive in the same turn:
- Re-read the plan file once and pre-emptively spot any gaps you would fix anyway.
- If the user has queued a related request (e.g. a second bug to bundle), investigate / draft plan text for it now so you are ready to act when Codex completes.
- Run sanity-check Bash one-liners that don't fork long-running processes (path checks, file existence, small `git log` queries).
- As an absolute last resort with no other useful work, call `AskUserQuestion` to ask a short clarifying question — `AskUserQuestion` is the only tool whitelisted for a legitimate session-pause while a background task is in flight.

The completion notification arrives automatically as a mid-turn tool-result-style event; you do not need to poll for it.

**Wait for completion via bash polling**, NOT by reading the state file directly while waiting. The polling bash returns when the job's `status` flips to `completed`/`failed`, which triggers the completion notification.

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

Run this as `Bash(run_in_background=true, timeout=600000)`. Plan reviews typically take 1–4 minutes (no diff context to load); the 10-minute ceiling is a safety margin.

1. **When (and ONLY when) the completion notification arrives**, fetch the result via the companion's public interface:

   ```bash
   node "$CODEX_COMPANION" result "$JOB_ID" --json > /tmp/codex-task-result-$$.json
   ```

   Read `/tmp/codex-task-result-$$.json` via `ctx_execute_file` (or Read for small payloads). The relevant fields:
   - `storedJob.status` — must be `"completed"`. If not, treat as a re-launch trigger; do not silently proceed.
   - `storedJob.result.rawOutput` — a string containing Codex's response. With our prompt, this is JSON matching the schema above.
   - `storedJob.rendered` — same content rendered for display; useful as a fallback if `rawOutput` is malformed.

2. **Parse `rawOutput` as JSON.** Extract `verdict`, `summary`, `findings`, `next_steps`. If `JSON.parse` fails (Codex deviated from the schema), fall back to `storedJob.rendered` — surface the rendered text to the user as a suggestion-level finding and continue. Do NOT re-launch on a parse failure; one Codex run per `/spec` is the rule.

   Severity → action map for the parsed findings:
   - `critical` / `high` → must_fix
   - `medium` / `low` → should_fix
   - `info` → suggestion

   Fix every must_fix and should_fix inline before requesting plan approval. Codex findings frequently surface architectural gaps (chained-command bypasses, fail-open paths, encoding edge cases) that the Claude reviewer misses — treat them with at least equal weight.

3. **If `storedJob.status` is `"failed"`** (genuine launch failure, not a timeout): re-launch synchronously and wait. If the second attempt also fails, escalate to the user with the captured error — do not silently proceed.

4. **Mark Codex as ran** so re-iterations of this plan within the same session do not re-run it:
```bash
mkdir -p "$(dirname "$CODEX_FLAG")" && touch "$CODEX_FLAG"
```

5. **Cleanup:** delete the temp prompt file:
```bash
rm -f "$PROMPT_FILE"
```

**If Codex was NOT launched**, proceed after all Claude reviewer must_fix/should_fix resolved.

## Step 11: Check for Console Annotation Feedback (Before Approval)

**⛔ Run this BEFORE Step 12 (approval).** Check if the user has annotated the plan in the Console's Specifications tab. Annotations auto-save to the unified JSON file — no "Send Feedback" button needed.

1. Derive the annotation file path from the plan path:
   - Plan: `docs/plans/2026-03-26-my-feature.md` → Annotations: `docs/plans/.annotations/2026-03-26-my-feature.json`

2. Read the annotation file with the Read tool. If the file doesn't exist, treat as `NO_FEEDBACK`. If it exists, check whether the `planAnnotations` array contains any entries (`FEEDBACK_EXISTS`) or is empty/missing (`NO_FEEDBACK`).

3. **If `FEEDBACK_EXISTS`:**
   - Each annotation in `planAnnotations` has `originalText` (selected text) and `text` (user's note)
   - Incorporate ALL annotations into the plan: treat each annotation's `text` as the user's instruction for that passage
   - After incorporating: delete the annotation file: `rm -f "<annotation-file-path>"` (e.g. `rm -f "docs/plans/.annotations/2026-03-26-my-feature.json"`). Direct file deletion is used instead of the DELETE API because curl is blocked in several hook environments.
   - Note: "Incorporated user annotations from Console — [N changes]"
   - Proceed to Step 12 with the updated plan

4. **If `NO_FEEDBACK`:** proceed directly to Step 12.

## Step 12: Get User Approval

**⛔ If `PILOT_PLAN_APPROVAL_ENABLED` is `"false"` (from Step 0),** skip this step: set `Approved: Yes` in the plan file automatically and immediately invoke `Skill(skill='spec-implement', args='<plan-path>')`. No AskUserQuestion, no notification.

**When `PILOT_PLAN_APPROVAL_ENABLED` is NOT `"false"` — MANDATORY APPROVAL GATE:**

0. Notify:

   ```bash
   ~/.pilot/bin/pilot notify plan_approval "Plan Ready for Review" "<plan_name> — annotate in Console or approve here" --plan-path "<plan_path>" 2>/dev/null || true
   ```

1. Summarize: goal, key tasks, approach

2. AskUserQuestion:
   - "Yes, proceed with implementation" — Approve as-is and start spec-implement (TDD loop)
   - "No, I have feedback" — I've annotated in the Console or edited the plan file; process my feedback

   The user can pause at this prompt, annotate in the Console's Specifications tab (annotations auto-save), or edit the plan file directly, then pick option 2. No "ready" handshake required.

   Note: `Worktree:` field was already set at creation time (Step 2). Do NOT ask again here.

3. **If "Yes":** Set `Approved: Yes`, invoke `Skill(skill='spec-implement', args='<plan-path>')`
   **If "No, I have feedback":** Re-run Step 11 (process Console annotations), re-read the plan file (in case the user edited it directly), then return to Step 12 and ask again.
   **If other free-text feedback (config values, threshold changes, clarifications):** This is NOT approval — incorporate the changes into the plan, then re-ask with a fresh AskUserQuestion.

ARGUMENTS: $ARGUMENTS