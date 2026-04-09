# /gsd:run-all

Run all remaining GSD phases end-to-end without interruption: plan → execute → repeat until done.

This is a wrapper around `/gsd:plan-phase` and `/gsd:execute-phase` that chains them automatically. It does NOT modify the GSD installation — it just orchestrates the existing commands in sequence.

## When to use

- Project has a ROADMAP.md with planned phases
- You want full automation: plan + execute each phase, one after another
- Config should have `mode: "yolo"` for best results (no mid-phase checkpoints)

## Process

**Step 1 — Load project state:**

```bash
INIT=$(node /Users/vigenerr/.claude/get-shit-done/bin/gsd-tools.cjs init progress)
```

Parse: `project_exists`, `phases`, `current_phase`, `phase_count`.

If `project_exists` is false: error — run `/gsd:new-project` first.

**Step 2 — Determine starting phase:**

```bash
ROADMAP=$(node /Users/vigenerr/.claude/get-shit-done/bin/gsd-tools.cjs roadmap analyze)
```

Parse the phases array. Find the first phase that is NOT `complete`. That is `START_PHASE`.

If no incomplete phases found: all done, show completion summary and exit.

**Step 3 — Display run plan:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 GSD ► AUTO RUN — {N} phases remaining
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Phases to execute:
  → Phase {X}: {name}
  → Phase {Y}: {name}
  ...

Running in YOLO mode — no interruptions.
```

**Step 4 — Execute each phase in sequence:**

For each incomplete phase (START_PHASE through last phase):

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 GSD ► PLANNING PHASE {N}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

4a. Invoke the plan-phase skill:

```
Use Skill tool: skill="gsd:plan-phase", args="{N}"
```

Wait for plan-phase to complete before continuing.

4b. Invoke the execute-phase skill:

```
Use Skill tool: skill="gsd:execute-phase", args="{N}"
```

Wait for execute-phase to complete before continuing.

4c. After each phase completes, reload state:

```bash
node /Users/vigenerr/.claude/get-shit-done/bin/gsd-tools.cjs roadmap analyze
```

Check if phase is now `complete`. If not, warn but continue.

**Step 5 — Final summary:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 GSD ► ALL PHASES COMPLETE ✓
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

{N} phases executed.

Next: /gsd:verify-work to validate or /gsd:complete-milestone to archive.
```

## Arguments

- No args: run all remaining phases from current position
- `--from N`: start from phase N (skip earlier phases)
- `--only N`: run only phase N (plan + execute)

## Notes

- Each phase is planned fresh before executing — no stale plans
- If a phase fails mid-execution, the run stops and surfaces the error
- CHANGELOG.md is updated by whichever phase handles it (usually the last)
- Works alongside `config.json` workflow settings (research, plan_check, verifier agents still run per their config)
