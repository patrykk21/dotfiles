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

**[Claude Code](./claude/)** — the generic half of a two-layer Claude Code setup: instructions, rules, skills, commands, agents, hooks, the status line, and the lists of tools and plugins every machine installs. Employer-specific material lives in a separate private repo cloned to `~/.claude`, under `company/<name>/`. `claude/bin/claude-link` merges both layers into `~/.claude` as symlinks, so skills keep their plain names.

Commands:
| Command | What it does |
|---------|-------------|
| `/conductor <url>` | Ticket-to-PR pipeline for Jira, ClickUp, Linear and GitHub tickets |
| `/dispatch <task>` | Background worker agents, one per task, steered from the main conversation |
| `/review [target]` | Multi-agent code review |
| `/fix-pr-comments` | Fetch and fix open PR review comments |
| `/create-ticket <desc>` | Structured Jira tickets via MCP |
| `/recap` | Where the branch and conversation stand |
| `/test` | Agent team that writes and runs tests for the branch |
| `/track <entry>` | Quick time-tracking log |
| `/new-worktree <ticket>` | Worktree + tmux session |
| `/agent-team <task>` | Agent team for parallel work |
| `/continue` | Resume the latest conversation in this directory |
| `/brag-book <item>` | Record an accomplishment for reviews |
| `/notion-entry` | Notion knowledge-base entry |
| `/fact-check` | Verify information accuracy |

Agents: `changes-review`, `spec-review` (each with a Codex variant), `web-search-agent`, `game-ui-ux-designer`.

**[Conductor](./conductor/)** — Autonomous ticket-to-PR pipeline. Tag a ticket, Claude implements it, opens a PR and comments back. Multi-project, cross-platform (macOS launchd / Linux systemd). See [conductor/README.md](./conductor/README.md).

```bash
# Manual: pass any ticket URL in a Claude session
/conductor https://your-org.atlassian.net/browse/PROJ-123

# Automated: scheduler polls Jira every 5 min
conductor add my-project
conductor on
conductor status
```

### Editors

**[Neovim](./nvim/)** — Lua-based config with Lazy.nvim, 40+ plugins. LSP, Treesitter, Telescope, Harpoon, NvChad UI, Git integration (gitsigns, neogit, diffview), auto-session, smart-splits.

**[Cursor](./cursor/)** — VSCode + Neovim integration, Tokyo Night theme, MCP servers (Jira, Tempo), 6 custom skills (create-rule, create-skill, create-subagent, shell, migrate-to-skills, update-settings).

**[Zed](./zed/)** — Vim mode, Tokyo Night, Claude AI integration.

### System

**[Aerospace](./aerospace/)** — macOS tiling window manager with workspace keybindings.

**[Zellij](./zellij/)** — Terminal workspace config (mostly replaced by tmux setup).

## Installation

### New machine (macOS, or Linux/WSL2 on Windows)

```bash
git clone https://github.com/patrykk21/dotfiles.git /tmp/dotfiles
/tmp/dotfiles/claude/bin/claude-bootstrap --secrets <file>
```

`claude-bootstrap` installs Homebrew and everything in `Brewfile`, clones this repo into `~/.config`, the private repo into `~/.claude` and the Work Console into `~/Work/work-console`, links the layers, installs Volta globals and plugins, and imports secrets. It ends with the sign-ins it can't do for you. It is safe to re-run.

- `<file>` comes from `~/.config/claude/bin/claude-secrets export <file>` on a machine that already has the secrets (MCP servers, conductor and console env files). It is passphrase-encrypted.
- Pass `--scheduler` on the one machine that should pick up tickets. Two schedulers would pick up the same tickets.
- On Windows, run it inside WSL2 (Ubuntu 24.04), with the WSL user's home at the same path as on the Mac. Absolute paths in the configs then match.

### Shell and editor

```bash
chsh -s "$(command -v zsh)"   # zsh as default shell
# tmux: open it and press Ctrl-Space + I to install plugins
nvim                          # Lazy.nvim installs its plugins on first start
```

## Conductor Setup

See [conductor/README.md](./conductor/README.md) for full instructions including:
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
  conductor.sh picks up ticket
        │
        ├─ git worktree add (isolated branch)
        ├─ create-worktree-session.sh (tmux: claude + server + commands)
        ├─ setup-worktree.sh hook (env files, launch.json, deps)
        ├─ dev server starts on assigned port
        │
        ▼
  Claude Code runs /conductor <ticket-url>
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
- **AI-first**: most dev tasks are one command away. `/spec` for planned implementation, `/review` for review, `/conductor` for full autonomy.
- **Platform-agnostic**: `/conductor` detects Jira, ClickUp, Linear, or GitHub Issues from the URL. The scheduler polls Jira and ClickUp; other platforms use a manual `/conductor` run.
- **Cross-platform**: Scripts use `$HOME`, `$(uname)` detection, and `setup.sh` generates the right scheduler for macOS or Linux.

## File Structure

```
~/.config/
├── tmux/              # 60 scripts, dual status bars, worktree integration
├── claude/            # Claude Code generic layer: instructions, rules, skills, commands, agents
├── conductor/         # Autonomous ticket-to-PR pipeline
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
