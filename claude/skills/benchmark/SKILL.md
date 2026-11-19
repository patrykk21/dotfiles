---
name: benchmark
description: Benchmark and evaluate rules, skills, and workflows with quantitative before/after comparisons. Use whenever the user wants to measure the impact of rules/skills/workflows, compare versions, or validate that a rule pack improves outputs.
user-invocable: true
---

# /benchmark — Benchmark & Evaluation Framework

Measure the real impact of rules and skills by running with/without comparisons, grading outputs against assertions, and presenting the findings inline.

## When to use this skill

- User wants to validate that a skill, rule, or rule pack actually improves outputs
- User says "benchmark", "evaluate", "measure", "before/after", "with vs without", "does this skill help?"
- User wants to extend a pilot eval matrix to more targets
- User wants to iterate on a skill or rule pack and needs quantitative feedback

## Supported target types

Two target types — both run in isolated `/tmp/pilot-bench-*` directories, one fresh directory per (eval, config, run):

| Target type | `with/` config | `without/` config | Use when |
|-------------|---------------|-------------------|----------|
<!-- CC-ONLY -->
| `skill` | Skill installed in `.claude/skills/<name>/` | Empty `.claude/` | Measuring "should we ship this skill?" |
| `rules` | Rule file(s) copied into `.claude/rules/` | Empty `.claude/` | Measuring "does this rule/pack improve behavior?" |
<!-- /CC-ONLY -->
<!-- CODEX-START
| `skill` | Skill installed in `.agents/skills/<name>/` | Empty root `AGENTS.md` | Measuring "should we ship this skill?" |
| `rules` | Rule file(s) composed into root `AGENTS.md` | Empty root `AGENTS.md` | Measuring "does this rule/pack improve behavior?" |
CODEX-END -->

Workflow-style skills like `/spec` are benchmarked as `type=skill` — present vs absent.

<!-- CC-ONLY -->
**Model selection:** Pilot-shipped skills (`spec-plan`, `fix`, `prd`, `create-skill`, `setup-rules`, …) don't carry a `model:` in their frontmatter — active model is controlled by Claude Code's `/model`. The runner defaults those benchmarks to `claude-sonnet-4-6`; pass `--model opus` explicitly to run them on Opus instead. Bot-* skills still carry hard-coded `model: sonnet`.
<!-- /CC-ONLY -->
<!-- CODEX-START
**Model selection:** When `--agent codex` is used and no `--model` is passed, the runner omits `--model` and lets Codex use its active default model. Pass an explicit Codex model with `--model` only when comparing models.
CODEX-END -->

## Isolation guarantees

- **Per-run filesystem sandbox.** Each (eval, config, run) triple gets its own `/tmp/pilot-bench-*/` cwd. Use relative paths in prompts, or the `{sandbox}` placeholder when you need an absolute path. Hardcoded `/tmp/<fixed-name>/` in prompts is flagged at load time.
<!-- CC-ONLY -->
- **Global-rule auto-hiding.** `~/.claude/rules/<basename>.md` and `~/.claude/skills/<name>/` are moved aside for the duration of the run when they duplicate the target, then restored automatically. Layered fail-safes (on-disk recovery manifest + atexit + SIGINT/SIGTERM/SIGHUP handlers + next-run sweep) make the restore robust against kill -9, power loss, and segfaults. Opt out with `--no-isolate-global` for realistic "day-to-day" measurement.
<!-- /CC-ONLY -->
<!-- CODEX-START
- **Global-skill auto-hiding.** `~/.agents/skills/<name>/` is moved aside for the duration of Codex skill benchmarks when it duplicates the target, then restored automatically. Codex rules benchmarks use an isolated root `AGENTS.md`; pass `--no-isolate-global` only when you intentionally want globally-installed skills present too.
CODEX-END -->

## Workflow

Follow these steps sequentially:

1. **Intake** (`steps/01-intake.md`) — Detect what the user wants to benchmark. If an existing `benchmarks/<target>/evals.json` exists, skip to execute.
2. **Target discovery** (`steps/02-target-discovery.md`) — Help the user pick a target and determine its type.
3. **Author evals** (`steps/03-author-evals.md`) — Draft 3 falsifiable, discriminating assertions for the target. Get user sign-off before spending compute.
4. **Execute** (`steps/04-execute.md`) — Run the runner, watch for failures, summarize results inline.
5. **Present findings** (`steps/05-review-iterate.md`) — Parse benchmark.json + per-run grading.json, render a per-eval matrix with evidence quotes in chat.
6. **Improvement plan** (`steps/06-improvement-plan.md`) — Classify each assertion into Signal / Baseline / Unreachable / Regression, propose concrete edits to the target or to evals.json, ask the user which path to take, apply & re-run.

## Quick reference

**Config path:** `benchmarks/<target-name>/evals.json`
**Outputs:** `benchmarks/<target-name>/runs/<timestamp>/`
<!-- CC-ONLY -->
**Runner:** `PYTHONPATH=~/.claude/skills/benchmark uv run python -m scripts.runner --config <evals.json> --skip-permissions`
<!-- /CC-ONLY -->
<!-- CODEX-START
**Runner:** `PYTHONPATH=~/.agents/skills/benchmark uv run python -m scripts.runner --config <evals.json> --skip-permissions --agent codex --grader-timeout 600`
CODEX-END -->

**Defaults worth knowing:**
- `--runs 1` (keeps token cost low; bump only for variance analysis)
- `--workers 4` (bump to `min(total_runs, 8)` for small eval sets so all runs land in one wave)
- `--model` is read from the target skill's frontmatter for Claude (alias → ID); rules and model-less Claude skills fall back to `claude-sonnet-4-6`; Codex defaults to the active Codex model unless `--model` is passed
- `--grader-model` defaults to the same model as `--model` so executor and grader stay matched
<!-- CODEX-START
- Codex child runs execute inside fresh non-git temp directories; the runner passes `--skip-git-repo-check` to every `codex exec` child automatically.
- Codex grading can run longer than Claude-style stream grading because the grader reopens transcript and output files. Use `--grader-timeout 600` for file-writing evals or after any `grader-failed` timeout so you do not burn a full rerun on a missing `grading.json`.
CODEX-END -->

# Step 1 — Intake

Figure out what the user wants to benchmark and whether they have eval config already.

## Ask the user

1. **What are you benchmarking?** If they named a target (skill name, rule file), proceed. If they were vague ("benchmark my setup", "see if my rules help"), ask them to name one specific artifact.
2. **Does `benchmarks/<target-name>/evals.json` already exist in this project?**
   - Yes → skip to Step 4 (Execute).
   - No → go to Step 2 (Target discovery) to determine type and path.

## Default conventions

- Target name defaults to the directory basename (e.g., `testing` for `pilot/rules/testing.md`, `create-skill` for `pilot/skills/create-skill/`).
- Config path: `benchmarks/<target-name>/evals.json` relative to the project root.
- Results path: `benchmarks/<target-name>/runs/<ISO-timestamp>/`.

## When evals already exist

Read the existing `benchmarks/<target>/evals.json` and summarize it back to the user:

- Target type and path
- Number of evals and their prompts (one-liner each)
- Whether there are prior runs committed under `runs/`

Confirm they want to re-run against the same config, then advance to Step 4.

## When target is ambiguous

If the user says something like "benchmark all my rules" or "test everything", push back:

- Benchmarks run per-target. Running 15 rules sequentially is ~30 min of compute.
- Start with ONE target — prove the eval set is falsifiable (baseline fails the assertions) — then copy the evals.json as a template for the next target.

## Exits

- Have target + evals → Step 4
- Have target, no evals → Step 2
- No target → ask again before spending compute

# Step 2 — Target discovery

Determine the target's type (`skill` or `rules`) and its path.

## Decide the type

| User's artifact | Target type |
|-----------------|-------------|
| A skill directory (contains `SKILL.md`) | `skill` |
| A single rule file (`.md`) | `rules` |
| A directory of rule files (no `SKILL.md`) | `rules` |
| A skill that the user wants to benchmark "as a workflow" | Still `skill` — present vs absent is the right baseline |

When in doubt, ask: "Is this a reusable skill (has `SKILL.md`) or a rule pack (plain `.md` files)?"

## Resolve the path

- Prefer repo-relative paths (`pilot/skills/create-skill`) over absolute paths — makes `evals.json` portable.
- Validate the path exists before advancing. If it doesn't, ask the user for the correct location.

## List candidates when needed

If the user can't remember exact names, list them:

```bash
<!-- CC-ONLY -->
# Skills in this project
ls -1 pilot/skills/ ~/.claude/skills/

# Rules in this project
ls -1 pilot/rules/ ~/.claude/rules/
<!-- /CC-ONLY -->
<!-- CODEX-START
# Skills in this project
ls -1 pilot/skills/ .agents/skills/ ~/.agents/skills/ 2>/dev/null

# Rules in this project
ls -1 pilot/rules/ .claude/rules/ 2>/dev/null
# Codex project rules are materialized from repo-root AGENTS.md when benchmarking.
CODEX-END -->
```

Skip Pilot internals like `bot-*` unless the user specifically asks for them.

## Emit the target block

Once resolved, write to the in-memory state:

```json
{
  "type": "skill | rules",
  "path": "pilot/skills/create-skill",
  "name": "create-skill"
}
```

The `name` field (optional) is used for the output directory name under `benchmarks/`. Default to the basename of `path` if the user didn't specify.

## Exit

Go to Step 3 (author evals).

# Step 3 — Author evals

Draft 3 realistic prompts with **falsifiable**, **discriminating** assertions. This is the highest-leverage step — bad assertions produce noise, not signal.

## Structure of evals.json

```json
{
  "target": {
    "type": "skill",
    "path": "pilot/skills/create-skill",
    "name": "create-skill"
  },
  "evals": [
    {
      "id": 1,
      "name": "short-descriptive-name",
      "prompt": "Realistic user task — phrased the way a real engineer would type it. Save outputs to {sandbox}/<filename>.",
      "expected_output": "1-line description of what success looks like",
      "expectations": [
        "Specific, observable assertion 1",
        "Specific, observable assertion 2",
        "Specific, observable assertion 3"
      ]
    }
  ]
}
```

## Path isolation — required

Each run gets its own filesystem sandbox. Prompts must reference that sandbox, not a shared absolute path, or the `with` and `without` runs will read each other's outputs.

Two safe ways to specify where outputs go:

| Approach | Example | When to use |
|----------|---------|-------------|
| **Relative paths** (preferred) | `Save the result to slugify.py` | The subprocess cwd is already the per-run sandbox, so bare filenames land in the right place. Simpler, fewer tokens. |
| **`{sandbox}` placeholder** | `Save to {sandbox}/slugify.py` | Use when the prompt genuinely needs an absolute path — the runner substitutes `{sandbox}` with the per-run directory before executing. |

**Never write `/tmp/<fixed-name>/file.py` in a prompt.** The runner emits a warning and proceeds, but the benchmark is invalid — both configs write to the same path.

## What makes an assertion good

**Discriminating.** The baseline (`without`) must plausibly FAIL the assertion. If both configs always pass it, the assertion measures nothing. The modern models already know "write tests, mock subprocess, use descriptive names" — assertions have to reach further than baseline habits to detect the rule's effect.

**Observable.** The grader reads the transcript and output files. Assertions like "the output is high quality" are unverifiable. Assertions like "the plan file contains sections named `## Summary`, `## Scope`, and `## Risks and Mitigations`" are observable.

**Genuine signal, not surface compliance.** "The output file is named `plan.md`" can pass by coincidence. Prefer "the plan.md contains a ### Task N heading for at least 3 tasks" — would pass only if the skill actually did structured task breakdown.

**Rule-specific, not industry common sense.** If the assertion tests common knowledge the base model already has (write some tests, avoid bare except), baseline passes and your rule gets no credit for teaching. Aim for the parts of the rule that are project-specific, stricter, or surprising — pytest marker requirements, exact naming patterns with multiple segments, coverage gates, property-based testing for parsers, mock-audit procedures.

## The falsifiability gate — mandatory

Before committing to a full eval set:

1. Hand-author one eval for this target.
2. Run baseline only:
<!-- CC-ONLY -->
   ```bash
   PYTHONPATH=~/.claude/skills/benchmark uv run python -m scripts.runner \
       --config benchmarks/<target>/evals.json --configs without --runs 1 \
       --skip-permissions
   ```
<!-- /CC-ONLY -->
<!-- CODEX-START
   ```bash
   PYTHONPATH=~/.agents/skills/benchmark uv run python -m scripts.runner \
       --config benchmarks/<target>/evals.json --configs without --runs 1 \
       --skip-permissions --agent codex --grader-timeout 600
   ```
CODEX-END -->
3. Inspect the baseline output (read `grading.json` for each run). If baseline passes 3/3 assertions, **rewrite the assertions** — they're not discriminating.

Only after the baseline fails at least one assertion do you have evidence that the eval measures something real. Skip the gate only when the user explicitly says they want a quick smoke test.

## Examples by type

**Skill target** (e.g., `/create-skill`):
- "Response includes a complete SKILL.md with `---` frontmatter containing `name:` and `description:` fields"
- "Response references the existing skill-creation pattern from `pilot/skills/create-skill/orchestrator.md`"
- "Response suggests at least one test prompt for the new skill"

**Rules target** (e.g., `testing.md` — aim past baseline habits):
- "Each new test function is decorated with `@pytest.mark.unit` — baseline Claude rarely adds this marker by default"
- "Test names match the regex `test_[a-z]+_[a-z_]+_[a-z_]+` (≥4 underscore-separated segments after `test`)"
- "The test file contains at least one property-based test using `hypothesis` (`@given(...)`) for parser/serializer behavior"
- "A coverage invocation like `pytest --cov-fail-under=80` appears in the transcript or a generated script"

## Commit the config

Save to `benchmarks/<target-name>/evals.json`. Show the user the final config and get explicit sign-off before spending compute in Step 4.

## Exit

Go to Step 4 (execute).

# Step 4 — Execute

<!-- CC-ONLY -->
Run the runner **in the background** so the user gets live status updates while it runs. Foreground bash blocks for the full duration (often 5-30 minutes) and shows nothing until the end — that's a bad UX, don't do it.
<!-- /CC-ONLY -->
<!-- CODEX-START
Run the runner with the Codex shell execution tool. If it yields a long-running session, keep the session id and poll it for status; otherwise read the command output directly when it completes.
CODEX-END -->

## Launch

<!-- CC-ONLY -->
Use the `Bash` tool with `run_in_background=true`. Capture the returned task ID; you will need it to read output and check completion.

```
Bash(
  command="PYTHONPATH=~/.claude/skills/benchmark uv run python -m scripts.runner \
    --config benchmarks/<target-name>/evals.json \
    --skip-permissions",
  description="Run benchmark in background",
  run_in_background=true,
)
```
<!-- /CC-ONLY -->
<!-- CODEX-START
```bash
PYTHONPATH=~/.agents/skills/benchmark uv run python -m scripts.runner \
  --config benchmarks/<target-name>/evals.json \
  --skip-permissions --agent codex --grader-timeout 600
```
CODEX-END -->

<!-- CC-ONLY -->
That's it for arguments — defaults handle the rest. The runner reads the target skill's `model:` frontmatter and uses that for both executor and grader. Rules targets and skills without a `model:` field fall back to `claude-sonnet-4-6`.
<!-- /CC-ONLY -->
<!-- CODEX-START
That's it for arguments — defaults handle the rest. With `--agent codex`, the runner installs skills in `.agents/skills/<name>/`, composes rules into root `AGENTS.md`, and omits `--model` unless you pass one explicitly so Codex uses its active default model.
CODEX-END -->

<!-- CODEX-START
Codex runs happen in freshly-created temp directories, which are intentionally not git repositories. The runner adds `--skip-git-repo-check` to each child `codex exec` automatically; if you see `Not inside a trusted directory and --skip-git-repo-check was not specified`, update or fix the runner before rerunning the benchmark.
CODEX-END -->

**Why `uv run`:** every Python invocation in this project uses `uv run` — no system `python` or `python3`. It ensures the right interpreter and dependency set.

<!-- CC-ONLY -->
**Why `--skip-permissions`:** all benchmark runs need this flag because `claude -p` is spawned non-interactively (no terminal to answer permission prompts). It passes `--dangerously-skip-permissions` to every executor and grader subprocess. Only use in a trusted environment — the grader reads arbitrary file paths passed by evals.json.
<!-- /CC-ONLY -->
<!-- CODEX-START
**Why `--skip-permissions`:** all benchmark runs need this flag because `codex exec` is spawned non-interactively. It configures full-access sandbox permissions for every executor and grader subprocess. Only use in a trusted environment — the grader reads arbitrary file paths passed by evals.json.
CODEX-END -->

<!-- CODEX-START
**Why `--grader-timeout 600`:** Codex graders reopen transcripts and generated files from disk, and artifact-heavy evals can exceed the 300s default even when executor runs succeed. Prefer starting Codex comparisons with 600s so a single slow grader does not force a full rerun just to produce `grading.json`.
CODEX-END -->

## Surface the plan header to the user immediately

<!-- CC-ONLY -->
As soon as the runner starts, it prints a plan header (config path, target, output dir, evals × configs × runs, models). Read it with `BashOutput` and relay it verbatim to the user so they see the scope and ETA up front:

```
BashOutput(bash_id="<task_id>")
```

Then send a brief intro to the user, e.g.:
<!-- /CC-ONLY -->
<!-- CODEX-START
As soon as the runner starts, it prints a plan header (config path, target, output dir, evals × configs × runs, models). Relay it verbatim to the user so they see the scope and ETA up front.

Then send a brief intro to the user, e.g.:
CODEX-END -->

> Benchmark started. **Plan:** 6 evals × 2 configs × 1 run = 12 runs, executor=<model>. Estimated ~30-45 min. I'll surface progress as runs complete and the final summary when it finishes.

## Status updates while it runs

The runner emits these stdout patterns to watch for:

| Pattern | When | What to do |
|---------|------|-----------|
| `[N/M] ✓ eval-X config run-N  78.3s, 12.4k tok  · ... ETA Xm` | Per completed run | Once you've seen >2 of these, you have an ETA — relay the latest ETA to the user when they ask or every ~5 min. |
| `· [snapshot Xs elapsed] N done · M in-flight · K queued · F failed` | Every 30s while in-flight | Use these as quick "still alive" pings. |
| `✗ eval-X config run-N  failed: <reason>` | On run failure | Surface immediately to the user — failures often mean config issues (timeout, missing agent CLI, grader-no-output). |

<!-- CC-ONLY -->
**You will be notified automatically when the background task completes** — do NOT sleep, poll, or proactively check on its progress. Continue with other work or respond to the user's questions in the meantime. When the user asks "how's it going?", call `BashOutput(bash_id=...)` to fetch the latest lines and summarize them.
<!-- /CC-ONLY -->
<!-- CODEX-START
If the shell tool returns a running session id, poll that session for the latest lines when the user asks "how's it going?" or when the session completes.
CODEX-END -->

## When the runner completes

The runner's tail of output includes a summary block:

```
────────────────────────────────────────────────────────────────────────
Benchmark complete in 33m14s  (12 ok, 0 failed, 0 skipped)
────────────────────────────────────────────────────────────────────────
  With Skill                   ok 6/6  avg 110.5s, 568k tok total
  Without Skill                ok 6/6  avg 78.2s, 138k tok total
────────────────────────────────────────────────────────────────────────
Wrote benchmarks/<target>/runs/<ts>/benchmark.json
```

Read the final output and:
1. Quote the summary block to the user
2. Compute and surface the headline `delta.pass_rate` from `benchmark.json` (signed string like `+0.50`)
3. Note any per-eval outliers if `stddev > 0.3`

## Flags (override the defaults when you have a reason)

| Flag | Default | When to override |
|------|---------|------------------|
| `--runs N` | `1` | `2-3` only when measuring variance — N runs are now parallelized across workers, so wall time grows sub-linearly. |
| `--model <id>` | Claude: skill frontmatter → `claude-sonnet-4-6`; Codex: active Codex default | Cross-model comparison. Claude accepts `opus`/`sonnet`/`haiku` aliases or explicit `claude-...` IDs. Codex passes the value directly to `codex exec --model`; omit it to use the active Codex model. |
| `--grader-model <id>` | same as `--model` | Run the grader at a different tier (rare — pairing them avoids "smart writer judged by dumb grader" artifacts). |
| `--configs with,without` | both | Smoke test one side. |
| `--workers N` | `4` | Drop to `2` when running opus to be kinder to rate limits. For small eval sets bump to `min(total_runs, 8)` so every run lands in the first wave (3 evals × 2 configs × 1 run = 6 → `--workers 6` cuts wall time roughly in half). The runner submits one pool task per (eval, config, run_idx) so workers stay saturated. |
<!-- CC-ONLY -->
| `--no-isolate-global` | off | Disable auto-hiding of globally-installed counterparts during the run. Claude hides matching `~/.claude/rules/<basename>.md` and `~/.claude/skills/<name>/`. Use only when you want to measure the target **in addition to** global guidance. |
<!-- /CC-ONLY -->
<!-- CODEX-START
| `--no-isolate-global` | off | Disable auto-hiding of globally-installed counterparts during the run. Codex hides matching `~/.agents/skills/<name>/`. Use only when you want to measure the target **in addition to** global guidance. |
CODEX-END -->
| `--restore-hidden` | off | Exit after recovering any `.pilot-bench-hidden-*` files left by a crashed prior run (normally swept automatically on every startup). |
| `--timeout <sec>` | `600` | Bump for slow models or large prompts. |
| `--grader-timeout <sec>` | `300` | Bump if `grader-no-output` failures appear. |
<!-- CODEX-START
| `--grader-timeout 600` | override | Recommended for Codex file-writing evals; it prevents a successful executor run from becoming an unusable partial result because the grader timed out while reading artifacts. |
CODEX-END -->
| `--output <dir>` | `benchmarks/<target>/runs/<ts>/` | Override when you want a specific output path. |

## Failure handling

When you see `failed.json` referenced (or a `✗ failed:` line):

- `reason: timeout` — bump `--timeout` or reduce `--runs`.
- `reason: no-result-event` — stream-json stream was malformed. Inspect `outputs/transcript.jsonl` for the raw stream.
<!-- CC-ONLY -->
- `reason: claude-cli-not-found` — the `claude` CLI isn't on PATH. Install Claude Code first.
<!-- /CC-ONLY -->
<!-- CODEX-START
- `reason: codex-cli-not-found` — the `codex` CLI isn't on PATH. Install Codex CLI first.
- `reason: codex-exec-failed` with `Not inside a trusted directory and --skip-git-repo-check was not specified` — the runner is missing the Codex temp-directory trust flag. Add `--skip-git-repo-check` to executor and grader `codex exec` commands, then rerun.
- `reason: grader-failed` with `timed out after 300 seconds` — rerun with `--grader-timeout 600`; the executor output is usually usable, but the missing `grading.json` makes the aggregate incomplete.
CODEX-END -->
- `reason: grader-no-output` / `grader-invalid-json` — the grader subagent failed. Retry or bump `--grader-model` a tier.

A few failed runs do not abort the rest of the benchmark — each writes its own `failed.json` and the runner continues. Surface failures to the user but only stop everything if more than half are failing.

## Commit the snapshot

Once the benchmark is stable (you've got a result you trust), commit `benchmarks/<target>/runs/<timestamp>/benchmark.json` as a baseline snapshot. Future runs can compare against it.

## Exit

Go to Step 5 (present findings & iterate).

# Step 5 — Present findings

The runner has finished. Read the artifacts directly and present findings inline — no external viewer.

This step is **reporting only**. Translating the findings into proposed edits happens in Step 6 (`steps/06-improvement-plan.md`). Always advance to Step 6 — a benchmark without a follow-up plan is a report card, not a tool.

## Goal

Render a report a busy user can absorb in **30 seconds** and act on. Lead with the verdict, surface the quadrant shape, then drill into divergent assertions only. Save full evidence and matching assertions for "tell me more".

## Artifacts to read

For the run directory `benchmarks/<target>/runs/<timestamp>/`:

| File | Purpose |
|------|---------|
| `benchmark.json` | Aggregate metrics + delta |
| `eval-N/eval_metadata.json` | Prompt + assertion list per eval |
| `eval-N/{with_skill,without_skill}/run-M/grading.json` | Per-assertion verdict + evidence + grader critiques |
| `eval-N/{with_skill,without_skill}/run-M/failed.json` | Present only when the run failed |

## Delta interpretation rubric (read this BEFORE writing the report)

The pass-rate delta from `benchmark.json → run_summary.delta.pass_rate` is the headline number. Map it to a label so the user knows whether to celebrate, iterate, or worry:

| `delta.pass_rate` | Label | What it means |
|---|---|---|
| **≥ +0.50** | 🟢 Strong signal | Rule clearly lifts model behavior. Ready to ship; consider expanding coverage. |
| **+0.20 to +0.49** | 🟢 Moderate signal | Rule helps. Worth shipping if the lift justifies the rule's maintenance cost. |
| **+0.05 to +0.19** | 🟡 Weak signal | Real but small. Either tighten assertions to expose a sharper effect, or strengthen the rule's language/examples. |
| **−0.05 to +0.04** | ⚪ Indistinguishable | Either assertions don't discriminate (most common — see Quadrant breakdown), or the rule isn't landing, or both. **Step 6 will diagnose which.** |
| **< −0.05** | 🔴 Regression | The rule actively misled the model. Investigate before shipping — Step 6 will name the regressing assertions. |

Stddev > 0.30 on any single eval = flaky/model-dependent — re-run with `--runs 3` before drawing conclusions.

## Compute quadrants in the same pass

For each `(eval, assertion)`, classify the `(with, without)` verdict pair:

| `with` | `without` | Quadrant | One-line meaning |
|---|---|---|---|
| ✓ | ✗ | **Signal** | Rule works here |
| ✓ | ✓ | **Baseline** | Eval doesn't discriminate |
| ✗ | ✗ | **Unreachable** | Rule isn't cutting through |
| ✗ | ✓ | **Regression** | Rule is making it worse — surface loudly |

Counting these up front lets the user see the shape immediately and gives Step 6 the input it needs.

## Presentation format — render in this order

### 1. One-line verdict + headline (always at the top)

```
VERDICT  🟢 Moderate signal — rule lifts pass rate from 0.33 to 0.78 (+0.44).
         Ship after addressing 1 Unreachable assertion (eval-1, #3).

         Pass rate     with 7/9 (0.78)   without 3/9 (0.33)   Δ +0.44 🟢
         Avg time      with 27.5s        without 25.9s        Δ +1.6s
         Avg tokens    with 200k         without 206k         Δ −6k
         Runs          3/3 ok            3/3 ok               0 failed
```

The verdict sentence has a **fixed shape**:
1. Emoji + label (from the rubric above)
2. Quantified claim using the delta and raw pass rates
3. Action hint pointing forward to Step 6 (e.g. "Ship after fixing the 1 regression" / "Tighten assertions before re-running" / "Investigate eval-2 regression")

If `delta.pass_rate` is in the **Indistinguishable** band, the verdict must say **why** based on the quadrant shape — otherwise the user doesn't know if the rule is broken or the evals are. Examples:
- Quadrant heavy in Baseline → "rule works but evals don't measure it; rewrite assertions"
- Quadrant heavy in Unreachable → "rule isn't landing; sharpen its cues"
- Mixed → "investigate per-eval — Step 6 will propose edits"

If any **Regression** assertions exist, surface them in the verdict regardless of overall delta.

### 2. Quadrant breakdown

```
Quadrant breakdown   (out of 9 assertions)
  🟢 Signal        5    rule works here
  ⚪ Baseline      3    eval doesn't discriminate (Step 6 will tighten)
  🟡 Unreachable   1    rule isn't cutting through (Step 6 will sharpen)
  🔴 Regression    0
```

This is the same data Step 6 needs — print it once here, refer back from Step 6 instead of recomputing.

### 3. Per-eval drill-down — divergent assertions only

For each eval, show **only** assertions where `with ≠ without` (Signal or Regression) plus any Regression assertions explicitly. Fold Baseline and Unreachable into a count summary so the user isn't drowned in matching rows.

```
Eval 1 — strict-tdd-naming-pbt          🟢×2  ⚪×0  🟡×1  🔴×0
  🟢 #1  Every test decorated with @pytest.mark.unit
         evidence (with):  "All 5 tests use @pytest.mark.unit decorator"
  🟢 #2  Test names follow strict 4-segment regex
         evidence (with):  "9 test names match test_slugify_<scenario>_<expected>"
  🟡 #3  ≥1 property-based test using hypothesis
         (both fail — rule doesn't teach hypothesis PBT)

Eval 2 — mock-audit-new-dependency       🟢×3  ⚪×0  🟡×0  🔴×0
  🟢 #1  BOTH pre-existing tests updated with subprocess mocks
         evidence (with):  "Both test_build_order_id_* updated with @patch"
  🟢 #2  Mock applied at module-of-consumption
         evidence (with):  "@patch('orders.subprocess.run') in all tests"
  🟢 #3  pytest run completes <1s wall time
         evidence (with):  "pytest finished in 0.04s, no real git invocation"
```

Quote evidence ≤ 200 chars. Drop matching assertions entirely from the body and fold them into the per-eval header counts so the row count stays low.

### 4. Grader-flagged critiques (only if any)

Walk each `grading.json` → `eval_feedback.suggestions`. These are the grader pointing out trivially-satisfied assertions or important uncovered behaviors. They feed directly into Step 6's eval-edit proposals.

```
Grader critiques
  eval-2 #3  "Wall-time check is loose — would also pass for a partially-mocked test
              that hits localhost. Consider asserting the mock was called instead."
```

Skip this section entirely when no critiques exist.

### 5. Failures (only if any)

If any run wrote `failed.json`, list them with reason + suggested fix. Don't bury these — a single failed run can flip the delta.

## Read the files efficiently

One sandbox script does the whole walk and prints the structured report. Keep grading blobs out of context — only the compact lines reach the user.

```python
import json
from pathlib import Path

run_dir = Path("benchmarks/<target>/runs/<timestamp>")
bm = json.loads((run_dir / "benchmark.json").read_text())
delta = float(bm["run_summary"]["delta"]["pass_rate"])

# Map delta to label per the rubric.
if delta >= 0.50:    label = "🟢 Strong signal"
elif delta >= 0.20:  label = "🟢 Moderate signal"
elif delta >= 0.05:  label = "🟡 Weak signal"
elif delta >= -0.05: label = "⚪ Indistinguishable"
else:                label = "🔴 Regression"

# Per-assertion quadrant classification + structured output.
quadrants = {"signal": 0, "baseline": 0, "unreachable": 0, "regression": 0}
for eval_dir in sorted(run_dir.glob("eval-*")):
    meta = json.loads((eval_dir / "eval_metadata.json").read_text())
    for i in range(len(meta["assertions"])):
        with_g = json.loads((eval_dir / "with_skill" / "run-1" / "grading.json").read_text())
        without_g = json.loads((eval_dir / "without_skill" / "run-1" / "grading.json").read_text())
        w = with_g["expectations"][i]["passed"]
        wo = without_g["expectations"][i]["passed"]
        if w and not wo:    quadrants["signal"] += 1
        elif w and wo:      quadrants["baseline"] += 1
        elif not w and wo:  quadrants["regression"] += 1
        else:               quadrants["unreachable"] += 1

print(f"VERDICT {label} — Δ pass-rate {delta:+.2f}")
print(f"Quadrants: signal={quadrants['signal']} baseline={quadrants['baseline']} "
      f"unreachable={quadrants['unreachable']} regression={quadrants['regression']}")
# ... then drill-down loop, divergent rows only ...
```

## Style rules

- **Verdict first, evidence second.** Top three lines should answer "did it work?" without scrolling.
- **One emoji per quadrant**, used consistently throughout the report. Don't introduce new emojis later.
- **Fold the ordinary, surface the divergent.** Matching assertions are summarized as counts, never enumerated as rows.
- **Cap evidence at 200 chars** per quote. Long evidence is a sign the assertion is too prosey.
- **No markdown headings deeper than `###`** — heavy headers compete with the data.
- **Skip empty sections.** No "Grader critiques (none)" filler — just don't print the header.

## Exit

Go to Step 6 (`steps/06-improvement-plan.md`) — translate quadrant counts into specific edits and ask the user which path to take.