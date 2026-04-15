---
name: agent-teams
description: >
  Use agent teams when tasks benefit from parallel, independent exploration with inter-agent communication:
  parallel code reviews from different angles, competing debugging hypotheses, independent module implementation,
  or cross-layer changes. Prefer over subagents when teammates need to share findings and coordinate directly.
  NOT for sequential tasks, same-file edits, or simple focused work.
version: 1.0.0
tags: [orchestration, parallel, agents, teams]
---

# Agent Teams Skill

Coordinate multiple Claude Code instances working as a team. Use this when tasks genuinely benefit from parallel, independent agents that can communicate with each other.

> Requires: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in settings.json (already enabled).

## When to Use Agent Teams

**Use agent teams for:**
- **Parallel code review** — multiple reviewers each applying a distinct lens (security, performance, test coverage) simultaneously
- **Competing hypotheses debugging** — teammates actively try to disprove each other's root cause theories
- **Independent module implementation** — teammates each own separate files/modules with no overlap
- **Cross-layer changes** — frontend, backend, and tests each owned by a different teammate
- **Multi-angle research** — UX, architecture, devil's advocate exploring the same problem independently

**Use subagents (Task tool) instead when:**
- Workers only need to report results back, no inter-agent coordination needed
- Tasks are sequential or have many dependencies
- Same files would be edited by multiple agents (conflict risk)
- Simple, focused tasks where coordination overhead isn't worth it

**Use single session when:**
- Routine changes, bug fixes, or simple features
- Tasks that require the full conversation history

## How to Start an Agent Team

Tell Claude what you want in natural language. Claude creates the team, spawns teammates, and coordinates:

```
Create an agent team to review PR #142. Spawn three reviewers:
- One focused on security implications
- One checking performance impact
- One validating test coverage
```

```
Spawn an agent team with 3 teammates to implement these 3 independent modules in parallel.
Each teammate owns their module exclusively — no shared files.
```

```
Users report a bug where X happens. Spawn 3 teammates to investigate competing hypotheses.
Have them challenge each other's theories like a scientific debate.
Update the findings doc with whatever consensus emerges.
```

## Decision Guide for Flows

When orchestrating work (in `/cook`, `/review`, `/execute`, etc.), apply this decision tree:

```
Is the work parallelizable?
  ├─ No → single session or subagents
  └─ Yes → Do workers need to share findings or communicate?
              ├─ No → subagents (Task tool, cheaper)
              └─ Yes → agent team
                          └─ Will agents edit the same files?
                                ├─ Yes → redesign tasks or use subagents
                                └─ No → agent team ✅
```

## Integration with Existing Flows

### /review — Prefer agent teams for large PRs or multi-dimension reviews

Instead of spawning concurrent subagents, create an agent team when reviewers need to reference each other's findings:

```
Create an agent team to review [target]:
- security-reviewer teammate: focus on auth, input validation, secrets
- performance-reviewer teammate: focus on queries, renders, bundle
- coverage-reviewer teammate: focus on test gaps and edge cases
Have them share findings and challenge each other before reporting to you.
```

### /cook — Use agent team when implementing independent modules

When the architectural plan identifies truly independent modules:

```
Create an agent team to implement the plan. Each teammate owns:
- Teammate 1: [module A - files x, y]
- Teammate 2: [module B - files a, b]  
- Teammate 3: [test suite - no overlap with implementation files]
Require plan approval before each teammate makes changes.
```

### Debugging — Use agent team for complex root cause analysis

```
Spawn 4 teammates to investigate this bug. Assign each a different hypothesis.
Have them report to each other and converge on the most likely root cause.
```

## Display Mode

The `teammateMode` in `~/.claude.json` controls how teammates appear:
- `"auto"` (default) — split panes if in tmux, in-process otherwise
- `"in-process"` — all in main terminal, Shift+Down to cycle through teammates
- `"tmux"` — each teammate gets its own pane

Navigate teammates: **Shift+Down** to cycle, **Ctrl+T** to toggle task list.

## Best Practices

- **3–5 teammates** is the sweet spot for most workflows
- **5–6 tasks per teammate** keeps everyone productive
- **No shared files** — each teammate should own a distinct set
- **Give context in spawn prompt** — teammates don't inherit lead's conversation history
- **Require plan approval** for risky or complex changes: "Require plan approval before they make any changes"
- **Clean up when done**: "Clean up the team" — always via the lead, not a teammate

## Limitations (experimental)

- No session resumption with in-process teammates (`/resume` won't restore them)
- Task status can lag — nudge the lead if a task appears stuck
- One team per session — clean up before starting a new one
- No nested teams — only the lead can spawn teammates
- Split panes require tmux or iTerm2 (not VS Code terminal or Windows Terminal)
