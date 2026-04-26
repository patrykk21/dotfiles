#!/usr/bin/env bash
# Shared OS detection and platform-agnostic helpers for launch-*.sh scripts.
# Source this file: source ~/.config/tmux/scripts/os-utils.sh

# detect_os: prints one of: macos, wsl, linux, windows
detect_os() {
    case "$OSTYPE" in
        darwin*) echo "macos" ;;
        msys*|cygwin*) echo "windows" ;;
        linux*)
            if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
                echo "wsl"
            else
                echo "linux"
            fi
            ;;
        *) echo "unknown" ;;
    esac
}

# open_url <url>: opens URL in the system default browser
open_url() {
    local url="$1"
    case "$(detect_os)" in
        macos)   open "$url" ;;
        wsl)     cmd.exe /c start "" "$url" 2>/dev/null ;;
        linux)   xdg-open "$url" >/dev/null 2>&1 & ;;
        windows) start "" "$url" ;;
        *)       echo "open_url: unsupported OS" >&2; return 1 ;;
    esac
}

# open_path <path>: opens a file/directory in the system default file manager
open_path() {
    local path="$1"
    case "$(detect_os)" in
        macos)   open "$path" ;;
        wsl)     explorer.exe "$(wslpath -w "$path")" 2>/dev/null ;;
        linux)   xdg-open "$path" >/dev/null 2>&1 & ;;
        windows) explorer "$path" ;;
        *)       echo "open_path: unsupported OS" >&2; return 1 ;;
    esac
}

# find_godot: prints absolute path to a usable Godot binary, or empty.
# Honors $GODOT env var first.
find_godot() {
    if [ -n "$GODOT" ] && [ -x "$GODOT" ]; then
        echo "$GODOT"
        return 0
    fi
    if command -v godot >/dev/null 2>&1; then
        command -v godot
        return 0
    fi
    case "$(detect_os)" in
        macos)
            for p in /Applications/Godot.app/Contents/MacOS/Godot /Applications/Godot_mono.app/Contents/MacOS/Godot; do
                [ -x "$p" ] && { echo "$p"; return 0; }
            done
            ;;
        wsl|linux)
            for p in "$HOME/.local/bin/godot" /usr/local/bin/godot /usr/bin/godot; do
                [ -x "$p" ] && { echo "$p"; return 0; }
            done
            ;;
    esac
    return 1
}
