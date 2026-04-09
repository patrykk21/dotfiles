# Dotfiles

AI-augmented development environment with autonomous workflows, worktree-based development, and 20+ specialized AI agents.

## Quick Start

```bash
git clone https://github.com/patrykk21/dotfiles.git ~/.config
source ~/.config/zsh/aliases.sh
```

## What's Inside

### Terminal & Shell

**[Tmux](./tmux/)** — Advanced multiplexer with Zellij-style keybindings (Ctrl-Space prefix), dual status bars, borderless panes, and deep git worktree integration. 60 scripts handle everything from session management to dev server port tracking.

Key scripts:
| Script | Purpose |
|--------|---------|
| `worktree-create.sh` | Create git worktree + tmux session |
| `worktree-picker-fzf.sh` | Interactive worktree switcher |
| `create-worktree-session.sh` | Initialize 3-tab session (claude, server, commands) |
| `worktree-metadata.sh` | Track ports, branches, paths per worktree |
| `get-server-port.sh` | Detect running dev server port |
| `session-switcher-fzf.sh` | Quick session switching with preview |
| `top-status-bar.sh` | Context-aware top bar with server info |
| `launch-*.sh` | Quick launchers for Cursor, Jira, PRs, localhost |

**[Zsh](./zsh/)** — Aliases, exports, fzf integration, zoxide (smart cd), and transient Starship prompts for clean terminal history.

**[Starship](./starship.toml)** — Ultra-minimal prompt: single character indicator, command duration, time. Nothing else.

**[Kitty](./kitty/)** — GPU-accelerated terminal with custom keybinds and theme.

**[Ghostty](./ghostty/)** — Lightweight modern terminal config.

### AI & Automation

**[Claude Code](./claude/)** — 22 custom commands, 8 skills, 20+ specialized agents, and the GSD (Get Shit Done) framework with 33 subcommands.

Commands:
| Command | What it does |
|---------|-------------|
| `/autopilot <url>` | Implement a ticket end-to-end from any platform (Jira, ClickUp, Linear, GitHub) |
| `/autopilot new-project` | Run full GSD lifecycle autonomously |
| `/cook <task>` | Architectural planning + implementation in one flow |
| `/review [target]` | Multi-agent code review (security, perf, quality, a11y) |
| `/explain <target>` | Deep architectural explanation without code changes |
| `/five-fifteen` | Generate weekly report from Jira, Tempo, Git, Asana |
| `/create-ticket <desc>` | Create structured Jira tickets via MCP |
| `/fix-pr-comments` | Fetch and fix open PR review comments |
| `/test` | Playwright browser tests on current branch |
| `/track <entry>` | Quick time tracking log |
| `/time-tracking` | Analyze Jira estimates vs Tempo actuals |
| `/new-worktree <ticket>` | Create worktree + tmux session |
| `/team <task>` | Spawn multi-agent team for parallel work |
| `/team-with-judge <task>` | Agent team with critical quality evaluator |
| `/continue` | Resume work from previous session |
| `/brag-book <item>` | Record accomplishment for reviews |
| `/notion-entry` | Create Notion knowledge base entries |
| `/fact-check` | Verify information accuracy |

Specialized agents: `code-quality-guardian`, `api-architect`, `react-component-creator`, `test-writer`, `refactor-specialist`, `database-integrator`, `deployment-engineer`, `ui-implementer`, `accessibility-guardian`, `state-manager`, `monitoring-expert`, `react-performance-optimizer`, `nextjs-page-builder`, `game-ui-ux-designer`, and 13 GSD-specific agents.

**[Autopilot](./autopilot/)** — Autonomous ticket-to-PR pipeline. Tag a Jira ticket, Claude implements it, creates a PR, comments back. Multi-project, cross-platform (macOS launchd / Linux systemd). Works with any ticket URL via `/autopilot`. See [autopilot/README.md](./autopilot/README.md) for full setup.

```bash
# Manual: pass any ticket URL in a Claude session
/autopilot https://your-org.atlassian.net/browse/PROJ-123

# Automated: scheduler polls Jira every 5 min
autopilot add my-project
autopilot on
autopilot status
```

### Editors

**[Neovim](./nvim/)** — Lua-based config with Lazy.nvim, 40+ plugins. LSP, Treesitter, Telescope, Harpoon, NvChad UI, Git integration (gitsigns, neogit, diffview), auto-session, smart-splits.

**[Cursor](./cursor/)** — VSCode + Neovim integration, Tokyo Night theme, MCP servers (Jira, Tempo), 6 custom skills (create-rule, create-skill, create-subagent, shell, migrate-to-skills, update-settings).

**[Zed](./zed/)** — Vim mode, Tokyo Night, Claude AI integration.

### System

**[Aerospace](./aerospace/)** — macOS tiling window manager with workspace keybindings.

**[Zellij](./zellij/)** — Terminal workspace config (mostly replaced by tmux setup).

## Installation

### Prerequisites

```bash
# macOS
brew install tmux neovim zsh starship jq curl git gh
brew install --cask kitty ghostty aerospace

# Claude Code CLI
# Follow: https://docs.anthropic.com/en/docs/claude-code
```

### Setup

```bash
# 1. Clone
git clone https://github.com/patrykk21/dotfiles.git ~/.config

# 2. Set zsh as default shell
chsh -s /bin/zsh

# 3. Install tmux plugins
# Open tmux, press Ctrl-Space + I

# 4. Open Neovim — Lazy.nvim auto-installs plugins
nvim

# 5. (Optional) Set up autopilot
autopilot setup                    # install scheduler
autopilot add my-project           # add a project
$EDITOR ~/.config/autopilot/projects/my-project.env
autopilot on                       # start polling
```

### Autopilot Setup

See [autopilot/README.md](./autopilot/README.md) for full instructions including:
- Jira credentials
- Multi-project config
- Project-level worktree hooks
- Cross-platform scheduler (macOS/Linux)

## Architecture: The Autonomous Dev Loop

```
Tag ticket in Jira
        │
        ▼
  Scheduler (launchd/systemd, every 5 min)
        │
        ▼
  autopilot.sh picks up ticket
        │
        ├─ git worktree add (isolated branch)
        ├─ create-worktree-session.sh (tmux: claude + server + commands)
        ├─ setup-worktree.sh hook (env files, launch.json, deps)
        ├─ dev server starts on assigned port
        │
        ▼
  Claude Code runs /autopilot <ticket-url>
        │
        ├─ Fetches ticket from Jira/ClickUp/Linear/GitHub
        ├─ Reads AGENTS.md / CLAUDE.md conventions
        ├─ Implements, tests, lints, typechecks
        ├─ Commits, pushes, creates PR
        ├─ Comments PR link on ticket
        │
        ▼
  Done. Next ticket.
```

## Key Design Decisions

- **Worktree-per-ticket**: Every ticket gets an isolated git worktree, its own tmux session, and its own dev server port. No branch switching, no conflicts.
- **Port management**: Ports auto-generated from worktree name hash (55000-56000 range), persisted in metadata JSON, propagated via `$SERVER_PORT` env var.
- **AI-first**: 22 Claude commands + 20 agents = most dev tasks are one command away. `/cook` for implementation, `/review` for review, `/autopilot` for full autonomy.
- **Platform-agnostic**: `/autopilot` detects Jira, ClickUp, Linear, or GitHub Issues from the URL. Scheduler polls Jira; other platforms use manual `/autopilot` invocation.
- **Cross-platform**: Scripts use `$HOME`, `$(uname)` detection, and `setup.sh` generates the right scheduler for macOS or Linux.

## File Structure

```
~/.config/
├── tmux/              # 60 scripts, dual status bars, worktree integration
├── claude/            # 22 commands, 8 skills, 20+ agents, GSD framework
├── autopilot/         # Autonomous ticket-to-PR pipeline
├── nvim/              # Lua config, 40+ plugins, LSP, Treesitter
├── cursor/            # VSCode+Neovim, MCP servers, 6 skills
├── zsh/               # Aliases, exports, fzf, zoxide, transient prompts
├── zed/               # Vim mode, Claude integration
├── aerospace/         # macOS tiling window manager
├── kitty/             # GPU terminal config
├── ghostty/           # Modern terminal config
├── zellij/            # Terminal workspace config
└── starship.toml      # Minimal prompt
```
