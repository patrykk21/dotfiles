#!/usr/bin/env bash
# Launch Cursor IDE in current directory

source ~/.config/tmux/scripts/os-utils.sh

CURRENT_DIR=$(tmux display-message -p '#{pane_current_path}')

case "$(detect_os)" in
    wsl)
        # On WSL, cursor.exe (Windows install) needs a Windows path.
        if command -v cursor.exe >/dev/null 2>&1; then
            cursor.exe "$(wslpath -w "$CURRENT_DIR")" >/dev/null 2>&1 &
        elif command -v cursor >/dev/null 2>&1; then
            cd "$CURRENT_DIR" && cursor . >/dev/null 2>&1 &
        else
            tmux display-message "Cursor not found (cursor.exe or cursor)"
            exit 1
        fi
        ;;
    macos|linux)
        if ! command -v cursor >/dev/null 2>&1; then
            tmux display-message "Cursor IDE not found in PATH"
            exit 1
        fi
        cd "$CURRENT_DIR" && cursor . >/dev/null 2>&1 &
        ;;
    *)
        tmux display-message "Unsupported OS: $(detect_os)"
        exit 1
        ;;
esac

tmux display-message "Launched Cursor in $CURRENT_DIR"