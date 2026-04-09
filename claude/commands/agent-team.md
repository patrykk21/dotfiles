---
description: Spawn an agent team for parallel work with inter-agent coordination. Use for multi-angle reviews, competing hypotheses debugging, independent module implementation, or cross-layer changes.
allowed-tools: TeamCreate, TeamDelete, SendMessage, Task, Read, Bash
---

# Agent Team Command

Spin up a coordinated team of Claude Code instances for: $ARGUMENTS

You are an agent team orchestrator. Analyze the task and create the most effective team structure.

## Step 1: Task Analysis

Determine the optimal team structure:
- How many teammates? (3–5 is the sweet spot)
- What is each teammate's distinct role/focus?
- Are the tasks truly independent (no shared files)?
- Does this warrant plan approval before implementation?

If the task is NOT a good fit for an agent team (sequential work, same-file edits, simple task), say so and suggest using subagents (Task tool) instead.

## Step 2: Spawn the Team

Tell Claude to create the team using natural language. Be explicit about:
- Team size and each teammate's role
- Whether plan approval is required before changes
- What files/areas each teammate owns
- How teammates should communicate findings to each other

Example prompts by use case:

**Parallel code review:**
```
Create an agent team to review [target]:
- security-reviewer: focus on auth, input validation, and data exposure
- performance-reviewer: focus on queries, renders, and bundle size  
- coverage-reviewer: focus on test gaps and missing edge cases
Have them share findings with each other before reporting back.
```

**Competing hypotheses debugging:**
```
Spawn [N] teammates to investigate: [bug description]
Each teammate investigates a different hypothesis:
- Teammate 1: [hypothesis A]
- Teammate 2: [hypothesis B]
- Teammate 3: [hypothesis C]
Have them actively try to disprove each other's theories.
Converge on consensus in a shared findings doc.
```

**Independent module implementation:**
```
Create an agent team to implement [feature]:
- Teammate 1: owns [module A] — files: [list]
- Teammate 2: owns [module B] — files: [list]
- Teammate 3: owns [test suite] — files: [list]
No teammate should touch another's files.
Require plan approval before any changes.
```

## Step 3: Monitor & Steer

- Use Shift+Down to cycle through teammates (in-process mode)
- Check in on progress, redirect approaches that aren't working
- Synthesize findings as they come in
- When done: "Clean up the team" — always through the lead

## Notes

- Teammates don't inherit lead's conversation history — include context in spawn prompt
- Token usage scales with team size — use only when coordination value justifies cost
- Clean up before starting a new team (one team per session)
