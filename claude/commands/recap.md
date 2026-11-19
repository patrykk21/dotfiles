---
name: recap
description: "Where the current branch and conversation stand: what it's for, what's done, what's left, what's blocking, plus PR and ticket status — in language a teammate can follow"
argument-hint: "[optional: 'full' for more detail, or a branch name / PR number to inspect instead of the current one]"
allowed-tools: ["Bash", "Read", "Grep", "Glob", "Skill", "mcp__atlassian__getJiraIssue"]
---

# Recap

Answer one question: **where does this work actually stand right now?**

The reader is a competent engineer who has not been in this session. They may be
you in two weeks, a teammate picking it up, or a lead asking for a status.

**Read-only. Never commit, push, merge, transition a ticket, comment on a PR, or
edit code from this command.** If the report surfaces something worth fixing, say
so and stop. Acting on it is a separate, explicit request.

`$ARGUMENTS` may name a branch or PR number to inspect instead of the current
checkout. Empty means the current branch.

## Step 1 — Gather evidence (run these in parallel, one message)

Detect the base branch rather than assuming — it differs per repo (`main-do`,
`main`, `master`, `staging`):

```bash
BASE=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
if [ -z "$BASE" ]; then
  for c in main-do main master staging develop; do
    git show-ref -q --verify "refs/remotes/origin/$c" && BASE="$c" && break
  done
fi
echo "base=$BASE  branch=$(git branch --show-current)"
```

Then collect:

```bash
git log --oneline "origin/$BASE..HEAD"          # commits this branch adds
git diff --stat "origin/$BASE...HEAD"           # scope of the change
git log -1 --format='%cr'                       # how stale
```

Uncommitted work — **use exit codes for the clean/dirty answer, not line counts.**
The RTK shell hook rewrites `git status --porcelain` and prints a literal `ok`
on a clean tree, so counting lines reports 1 change when there are none. Dirty
trees do pass real porcelain through.

```bash
git diff --quiet        || echo "unstaged changes present"
git diff --cached --quiet || echo "staged changes present"
git status --porcelain | grep -v '^ok$'   # listing; empty means clean
```

PR, CI, and review state (`gh` picks the right host from the repo remote, so this
works on both github.com and GitHub Enterprise hosts):

```bash
gh pr view --json number,title,state,isDraft,mergeable,reviewDecision,url,headRefName,body 2>/dev/null
gh pr view --json reviews,comments 2>/dev/null
```

`gh pr checks` needs the number passed explicitly under the RTK hook — bare, it
fails with `rtk: PR number required`. Take the number from the `gh pr view` output:

```bash
gh pr checks "$PR_NUMBER" 2>/dev/null
```

Handle "no PR yet" as a normal outcome, not an error.

Ticket, when the branch name carries a key (`PROJ-930-…`, `WEB-34334-…`,
`API-9024-…` — pattern `[A-Z][A-Z0-9]+-[0-9]+`): fetch it with
`mcp__atlassian__getJiraIssue` (cloudId: the `JIRA_BASE_URL` site URL from
`~/.claude/company/*/company.env`)
for summary, status, and assignee. If there is no key, say so and move on.

## Step 2 — Reconcile the conversation against the evidence

This is the part a plain `git log` cannot do, and it is the main value here.

From the session, extract: the goal, decisions made, things tried and abandoned,
questions asked of the user, and anything declared done.

Then check each claim against Step 1:

- "Tests pass" — was a test run actually executed in this session? If not, it is
  **unverified**, not done.
- "Fixed X" — is there a commit or a working-tree change that does it? Uncommitted
  work is real but at risk; say which.
- "Waiting on CI" — what does `gh pr checks` say right now?
- Decisions the user made in conversation that the code does not yet reflect.

**Where the conversation and the evidence disagree, the evidence wins, and say so
explicitly.** Silent divergence is the failure this command exists to catch.

## Step 3 — Write the report

Lead with the honest headline. Do not bury a blocker under a list of wins.

```
## <TICKET-KEY or branch> — <what this work is for, one line>

**Where it stands:** <one or two sentences. If blocked, that goes first.>

### Done
- <outcome, with the evidence: a commit, a file, an observed behaviour>

### Left
- <what remains, and what it depends on>

### Blocked
- <what is stuck, on whom or what, and what would unblock it>
- omit this section entirely if nothing is blocked — do not pad it

### Unverified
- <claimed complete but never actually run or checked>
- omit if everything is verified

### PR
<number, title, draft/open/merged, CI result, review decision, URL>
<or: "No PR yet — N commits ahead of BASE, not pushed">

### Ticket
<key, summary, status, assignee — or "no ticket key in the branch name">

### Needs your call
- <open questions or decisions waiting on the user>
- omit if none
```

With `full`, add: the per-file diff summary, individual CI check names and their
results, and unresolved review comments quoted with the file and line.

## Writing rules

Follow `~/.claude/rules/plain-language.md`. It is already mandatory for every
human-facing surface, and a status report is one. Load the `explain-simply`
skill if a passage resists being made clear.

The parts that matter most here:

- Assume industry fluency. Never define PR, commit, merge, CI, endpoint, cache,
  rebase, or similar. Explaining what the reader already knows reads as
  condescension.
- Gloss only project-internal names on first use — the name plus its role.
  "*Feedwise* — the third-party service currently picking the homepage rows."
- Short causal sentences, one idea each. "The token was rejected. Without it,
  conductor cannot transition the ticket."
- Never announce the register. No "simply", "in plain terms", "the short version".
- Every claim traceable to something the reader can open: a file, a line, a
  command's output, an observed behaviour.

## Honesty rules

- **State uncertainty as uncertainty.** "CI status unknown — no PR exists yet"
  beats a confident guess.
- **Do not inflate.** Three commits of scaffolding is not "the feature is built".
- **Do not deflate either.** If the work is genuinely finished and verified, say
  so plainly without hedging.
- **Separate observed from inferred.** "The PR is failing `lint`" is observed.
  "Probably the Biome config" is inferred — mark it as such.
- **Name what you could not check.** A missing `gh` auth, an unreachable Jira, a
  repo with no remote: report the gap rather than omitting the section.
