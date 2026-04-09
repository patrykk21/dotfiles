#!/usr/bin/env python3
"""
ai-usage-aggregator.py — deterministic per-day AI usage extractor for /eod.

Reads Claude Code session transcripts under ~/.claude/projects/-*/*.jsonl for a
given date and emits a structured JSON summary to
~/.claude/daily-reporting/ai-usage/YYYY-MM-DD.json.

The /eod skill (daily-reporting) calls this at runtime instead of asking Claude
to parse transcripts by hand. Same machine, same day → same output.

Pure stdlib. No network. No external deps.

Usage:
  python3 ai-usage-aggregator.py                               # today
  python3 ai-usage-aggregator.py --date 2026-04-09
  python3 ai-usage-aggregator.py --registry ~/.claude/eod-projects.json
  python3 ai-usage-aggregator.py --stdout                      # print instead of write
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

AGGREGATOR_VERSION = "1.0.0"

PLANS_RE = re.compile(r"docs/ai/plans/.*\.md$", re.IGNORECASE)
SPECS_RE = re.compile(
    r"docs/ai/(specs|designs|architecture|research|decisions)/.*\.md$",
    re.IGNORECASE,
)
MEMORY_RE = re.compile(r"\.claude/projects/[^/]+/memory/.*\.md$")


def mangle_path(path: str) -> str:
    """Convert a filesystem path to the Claude projects dirname mangling.

    /Users/foo/bar → -Users-foo-bar
    """
    return "-" + path.lstrip("/").replace("/", "-")


def load_registry(registry_path: Path) -> list[dict]:
    """Load eod-projects.json; return [] if missing or malformed."""
    if not registry_path.exists():
        return []
    try:
        data = json.loads(registry_path.read_text())
        return [p for p in data.get("projects", []) if p.get("enabled", True)]
    except (json.JSONDecodeError, OSError):
        return []


def build_project_index(registry: list[dict]) -> list[tuple[str, str]]:
    """Return [(mangled_prefix, project_id)] sorted longest-prefix-first.

    Longest-first ordering lets a nested path (e.g. `-Users-me-repo-apps-x`)
    still attribute to its parent project (`repo`) via prefix match, while
    more-specific registry entries win over less-specific ones.
    """
    items: list[tuple[str, str]] = []
    for p in registry:
        path = p.get("path", "")
        if not path:
            continue
        path = str(Path(path).expanduser())
        mangled = mangle_path(path)
        pid = p.get("id", Path(path).name)
        items.append((mangled, pid))
    items.sort(key=lambda x: -len(x[0]))
    return items


def lookup_project(dir_name: str, index: list[tuple[str, str]]) -> str | None:
    """Match a Claude projects dir name to a registry project id."""
    for mangled, pid in index:
        if dir_name == mangled or dir_name.startswith(mangled + "-"):
            return pid
    return None


def iter_transcripts():
    """Yield (project_dir_name, jsonl_path) for every transcript on disk."""
    projects_root = Path.home() / ".claude" / "projects"
    if not projects_root.exists():
        return
    for project_dir in projects_root.iterdir():
        if not project_dir.is_dir():
            continue
        for jsonl in project_dir.glob("*.jsonl"):
            yield project_dir.name, jsonl


def new_session_stats() -> dict:
    return {
        "has_activity": False,
        "tool_calls": Counter(),
        "mcp_servers": Counter(),
        "files_edited": set(),
        "skills_invoked": Counter(),
        "agents_dispatched": Counter(),
        "plans_written": 0,
        "specs_written": 0,
        "memory_updates": 0,
    }


def process_transcript(jsonl_path: Path, target_date: str) -> dict | None:
    """Extract AI signals from one transcript file for the target date.

    Returns None if no activity on that date. Corrupt lines are skipped.
    """
    stats = new_session_stats()
    try:
        with jsonl_path.open() as f:
            for line in f:
                try:
                    rec = json.loads(line)
                except json.JSONDecodeError:
                    continue
                ts_str = rec.get("timestamp", "")
                if not ts_str.startswith(target_date):
                    continue
                stats["has_activity"] = True

                if rec.get("type") == "assistant":
                    for block in rec.get("message", {}).get("content", []):
                        if isinstance(block, dict) and block.get("type") == "tool_use":
                            _process_tool_use(block, stats)
    except OSError:
        return None
    return stats if stats["has_activity"] else None


def _process_tool_use(block: dict, stats: dict) -> None:
    """Update stats with signals from a single tool_use block."""
    name = block.get("name", "")
    inp = block.get("input") if isinstance(block.get("input"), dict) else {}
    if not name:
        return

    stats["tool_calls"][name] += 1

    # MCP call grouping — mcp__<server>__<tool>
    if name.startswith("mcp__"):
        parts = name.split("__", 2)
        if len(parts) >= 2 and parts[1]:
            stats["mcp_servers"][parts[1]] += 1

    # Skill invocations — only real Skill tool uses, via the `skill` input field.
    # Never string-parse transcript content: the showcase JSON did that and
    # picked up path fragments like "wiki", "json", "null" as false positives.
    if name == "Skill":
        skill = str(inp.get("skill", "")).strip()
        if skill:
            stats["skills_invoked"][skill] += 1

    # Agent dispatches — the Agent tool carries subagent_type in its input.
    if name == "Agent":
        subagent = str(inp.get("subagent_type", "")).strip()
        if subagent:
            stats["agents_dispatched"][subagent] += 1

    # File edits — track unique paths + categorise plans / specs / memory.
    if name in ("Write", "Edit", "NotebookEdit"):
        fp = str(inp.get("file_path", "")).strip()
        if fp:
            stats["files_edited"].add(fp)
            if PLANS_RE.search(fp):
                stats["plans_written"] += 1
            elif SPECS_RE.search(fp):
                stats["specs_written"] += 1
            if MEMORY_RE.search(fp):
                stats["memory_updates"] += 1


def merge_project_stats(dest: dict, src: dict) -> None:
    """Merge a per-session stats dict into a per-project accumulator."""
    if not dest:
        dest.update(new_session_stats())
        dest["sessions"] = 0
    dest["sessions"] += 1
    dest["tool_calls"].update(src["tool_calls"])
    dest["mcp_servers"].update(src["mcp_servers"])
    dest["files_edited"].update(src["files_edited"])
    dest["skills_invoked"].update(src["skills_invoked"])
    dest["agents_dispatched"].update(src["agents_dispatched"])
    dest["plans_written"] += src["plans_written"]
    dest["specs_written"] += src["specs_written"]
    dest["memory_updates"] += src["memory_updates"]


def finalize_project(stats: dict) -> dict:
    """Convert a project accumulator into a JSON-serialisable dict."""
    return {
        "sessions": stats["sessions"],
        "tool_calls": dict(stats["tool_calls"].most_common()),
        "mcp_servers": dict(stats["mcp_servers"].most_common()),
        "mcp_calls_total": sum(stats["mcp_servers"].values()),
        "files_edited_count": len(stats["files_edited"]),
        "skills_invoked": dict(stats["skills_invoked"].most_common()),
        "agents_dispatched": dict(stats["agents_dispatched"].most_common()),
        "plans_written": stats["plans_written"],
        "specs_written": stats["specs_written"],
        "memory_updates": stats["memory_updates"],
    }


def compute_totals(projects: dict[str, dict]) -> dict:
    """Aggregate raw-accumulator projects into totals (before finalization)."""
    all_tool_calls: Counter = Counter()
    all_mcp: Counter = Counter()
    all_files: set[str] = set()
    all_skills: Counter = Counter()
    all_agents: Counter = Counter()
    plans = specs = memory = sessions = 0

    for p in projects.values():
        sessions += p["sessions"]
        all_tool_calls.update(p["tool_calls"])
        all_mcp.update(p["mcp_servers"])
        all_files.update(p["files_edited"])
        all_skills.update(p["skills_invoked"])
        all_agents.update(p["agents_dispatched"])
        plans += p["plans_written"]
        specs += p["specs_written"]
        memory += p["memory_updates"]

    return {
        "sessions": sessions,
        "unique_projects": len(projects),
        "total_tool_calls": sum(all_tool_calls.values()),
        "total_files_edited": len(all_files),
        "tool_calls": dict(all_tool_calls.most_common()),
        "mcp_calls_total": sum(all_mcp.values()),
        "mcp_servers": dict(all_mcp.most_common()),
        "skills_invoked": dict(all_skills.most_common()),
        "agents_dispatched": dict(all_agents.most_common()),
        "plans_written": plans,
        "specs_written": specs,
        "memory_updates": memory,
        "most_used_skill": (all_skills.most_common(1)[0][0] if all_skills else None),
        "most_used_agent": (all_agents.most_common(1)[0][0] if all_agents else None),
    }


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Aggregate Claude Code AI usage for /eod."
    )
    ap.add_argument(
        "--date",
        default=datetime.now().strftime("%Y-%m-%d"),
        help="Target date (YYYY-MM-DD). Defaults to today.",
    )
    ap.add_argument(
        "--registry",
        default=str(Path.home() / ".claude" / "eod-projects.json"),
        help="Path to eod-projects.json.",
    )
    ap.add_argument(
        "--output",
        default=None,
        help="Output JSON path (defaults to ~/.claude/daily-reporting/ai-usage/<date>.json).",
    )
    ap.add_argument(
        "--stdout",
        action="store_true",
        help="Print JSON to stdout instead of writing to disk.",
    )
    args = ap.parse_args()

    target_date = args.date
    registry = load_registry(Path(args.registry).expanduser())
    project_index = build_project_index(registry)

    projects: dict[str, dict] = {}
    for dir_name, jsonl in iter_transcripts():
        session = process_transcript(jsonl, target_date)
        if not session:
            continue
        pid = lookup_project(dir_name, project_index)
        if pid is None:
            # Session ran outside any registered project path — skip it.
            # TODO: expose a --include-unregistered flag to opt into ALL usage
            # (set via /daily-reporting-setup when the engineer wants full
            # coverage beyond their registered projects).
            continue
        merge_project_stats(projects.setdefault(pid, {}), session)

    totals = compute_totals(projects)

    output = {
        "_aggregator_version": AGGREGATOR_VERSION,
        "_generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "date": target_date,
        "projects": {pid: finalize_project(p) for pid, p in projects.items()},
        "totals": totals,
    }

    payload = json.dumps(output, indent=2) + "\n"

    if args.stdout:
        sys.stdout.write(payload)
        return 0

    out_path = (
        Path(args.output).expanduser()
        if args.output
        else Path.home() / ".claude" / "daily-reporting" / "ai-usage" / f"{target_date}.json"
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(payload)
    print(f"Wrote {out_path} ({out_path.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
