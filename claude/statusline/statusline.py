#!/usr/bin/env python3
"""Claude Code status line: model, context use, and the repo and branch the session runs in."""
import json
import os
import re
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
CACHE_DIR = os.path.join(HOME, ".cache", "statusline")
PILOT = os.path.join(HOME, ".pilot", "bin", "pilot")

PILOT_THROTTLE = 2
STAMP_MAX_AGE = 86400
MAX_WIDTH = 110

ANSI = re.compile(r"\x1b\[[0-9;]*m")


def visible_len(s):
    return len(ANSI.sub("", s))


def truncate(s, n):
    if n <= 0:
        return ""
    return s if len(s) <= n else s[: n - 1] + "…"


def git_info(start):
    d = os.path.abspath(start)
    while True:
        dot = os.path.join(d, ".git")
        if os.path.isdir(dot):
            return {"main": d, "gitdir": dot}
        if os.path.isfile(dot):
            try:
                with open(dot) as f:
                    line = f.read().strip()
            except OSError:
                return None
            if line.startswith("gitdir:"):
                gitdir = os.path.normpath(os.path.join(d, line[7:].strip()))
                common = gitdir
                commondir = os.path.join(gitdir, "commondir")
                if os.path.isfile(commondir):
                    with open(commondir) as f:
                        common = os.path.normpath(os.path.join(gitdir, f.read().strip()))
                main = os.path.dirname(common) if os.path.basename(common) == ".git" else d
                return {"main": main, "gitdir": gitdir}
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def read_branch(gitdir):
    try:
        with open(os.path.join(gitdir, "HEAD")) as f:
            head = f.read().strip()
    except OSError:
        return ""
    return head[len("ref: refs/heads/"):] if head.startswith("ref: refs/heads/") else head[:7]


def format_line(data, git):
    model = (data.get("model") or {}).get("display_name") or "Claude"
    pct = (data.get("context_window") or {}).get("used_percentage")
    if pct is None:
        ctx = "\x1b[2mctx --\x1b[0m"
    else:
        color = "32" if pct < 60 else "33" if pct < 80 else "31"
        ctx = f"ctx \x1b[{color}m{round(pct)}%\x1b[0m"
    parts = [f"\x1b[36m{model}\x1b[0m", ctx]
    if git:
        parts.append(f"{os.path.basename(git['main'])} \x1b[2m▸\x1b[0m \x1b[35m{read_branch(git['gitdir'])}\x1b[0m")
    return " \x1b[2m·\x1b[0m ".join(parts)


def stamp_is_fresh(path, ttl, now):
    try:
        return now - os.path.getmtime(path) < ttl
    except OSError:
        return False


def detach(cmd, stdin_bytes):
    try:
        p = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
            close_fds=True,
        )
        p.stdin.write(stdin_bytes)
        p.stdin.close()
    except OSError:
        pass


def prune_stamps(now):
    for name in os.listdir(CACHE_DIR):
        path = os.path.join(CACHE_DIR, name)
        if name.startswith("pilot-") and not stamp_is_fresh(path, STAMP_MAX_AGE, now):
            try:
                os.remove(path)
            except OSError:
                pass


def feed_pilot(raw, data, now):
    # Pilot's context monitor reads the context % that its own status line writes.
    if not os.path.isfile(PILOT):
        return
    os.makedirs(CACHE_DIR, exist_ok=True)
    stamp = os.path.join(CACHE_DIR, f"pilot-{data.get('session_id') or 'none'}")
    if stamp_is_fresh(stamp, PILOT_THROTTLE, now):
        return
    if not os.path.exists(stamp):
        prune_stamps(now)
    with open(stamp, "a"):
        os.utime(stamp, None)
    detach([PILOT, "statusline"], raw.encode())


def render():
    raw = sys.stdin.read()
    try:
        data = json.loads(raw) if raw.strip() else {}
    except ValueError:
        data = {}
    feed_pilot(raw, data, time.time())

    ws = data.get("workspace") or {}
    git = git_info(ws.get("current_dir") or data.get("cwd") or os.getcwd())
    width = min(int(os.environ.get("COLUMNS") or 100), MAX_WIDTH) - 1
    line = format_line(data, git)
    if visible_len(line) > width:
        line = truncate(ANSI.sub("", line), width)
    sys.stdout.write(line + "\n")


if __name__ == "__main__":
    try:
        render()
    except Exception as e:  # a broken status line must never hide the session state entirely
        sys.stdout.write(f"\x1b[31mstatus line error: {e}\x1b[0m\n")
