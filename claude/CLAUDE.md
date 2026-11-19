# Global instructions

## Priority rules
1. Before writing code against a library, framework or SDK, look up its current docs with context7.
2. Ticket work happens in its own git worktree, one per ticket and repo (see Worktrees).
3. Don't create files unless the task needs them; prefer editing existing ones.
4. Don't create docs or READMEs unless asked.

## How this setup is layered
- `~/.config/claude` is the generic layer, in the public dotfiles repo: these instructions, rules, skills, commands, agents, hooks and the status line. It must never name an employer, its systems, hosts, ticket keys or people.
- `~/.claude/company/<name>/` is the employer layer, in the private `~/.claude` repo: that employer's rules, skills, commands, agents and `company.env` (non-secret settings such as the Jira URL).
- `~/.claude/{skills,commands,agents,rules}` hold only symlinks, built by `~/.config/claude/bin/claude-link`. To add or change one, edit it in the right layer and re-run `claude-link`.
- Every machine (the Mac and the Windows machine's WSL2) must end up identical. A change reaches them only through the two repos, so nothing gets configured on one machine alone.

## Accounts
- `github-personal` is the personal GitHub account. Use it only for personal repos; it has no org access.
- Employer accounts and hosts are in that employer's layer.

## Worktrees
- Code projects on the Work Console: `wc start KEY` creates the worktree, tmux session and Claude window through conductor.
- Otherwise `git worktree add` from the repo's base branch.

## Agent teams
Enabled (experimental). The agent-teams skill says when a team beats plain subagents.

@RTK.md
