#!/usr/bin/env python3
"""Parse an Instagram data export and extract one DM thread.

    python3 parse_export.py <export_root> <name_substring> [outdir]

Writes <outdir>/<slug>.transcript.txt, <slug>.messages.json, <slug>.audio.txt
"""
import json
import pathlib
import sys
from datetime import datetime, timezone


def demojibake(s):
    """Instagram writes UTF-8 bytes escaped as latin-1. Undo it."""
    if not isinstance(s, str):
        return s
    try:
        return s.encode("latin-1").decode("utf-8")
    except (UnicodeEncodeError, UnicodeDecodeError):
        return s


def find_thread_dirs(root, needle):
    """Thread dirs are named <title>_<hash>; match on the title part."""
    needle = needle.lower()
    hits = []
    for inbox in root.rglob("messages/inbox"):
        for d in inbox.iterdir():
            if d.is_dir() and needle in d.name.lower():
                hits.append(d)
    return hits


def load_messages(thread_dir):
    msgs, participants, title = [], [], None
    files = sorted(thread_dir.glob("message_*.json"))
    if not files:
        return msgs, participants, title
    for f in files:
        data = json.loads(f.read_text(encoding="utf-8"))
        if title is None:
            title = demojibake(data.get("title") or "")
        for p in data.get("participants", []):
            n = demojibake(p.get("name", ""))
            if n and n not in participants:
                participants.append(n)
        msgs.extend(data.get("messages", []))
    return msgs, participants, title


def normalise(m, thread_dir, root):
    ts = m.get("timestamp_ms")
    when = (
        datetime.fromtimestamp(ts / 1000, tz=timezone.utc).astimezone()
        if ts
        else None
    )

    audio = []
    for a in m.get("audio_files") or []:
        uri = a.get("uri", "")
        p = root / uri
        if not p.exists():
            # Older exports store a path relative to the thread dir.
            alt = thread_dir / pathlib.Path(uri).name
            p = alt if alt.exists() else p
        audio.append(str(p))

    photos = [ph.get("uri", "") for ph in (m.get("photos") or [])]
    share = (m.get("share") or {}).get("link", "")

    reactions = [
        f"{demojibake(r.get('reaction',''))}<-{demojibake(r.get('actor',''))}"
        for r in (m.get("reactions") or [])
    ]

    return {
        "ts": when.isoformat() if when else None,
        "ts_ms": ts,
        "sender": demojibake(m.get("sender_name", "")),
        "content": demojibake(m.get("content", "")),
        "audio": audio,
        "photos": photos,
        "share": share,
        "reactions": reactions,
    }


def main():
    if len(sys.argv) < 3:
        print(__doc__.strip())
        sys.exit(2)

    root = pathlib.Path(sys.argv[1]).expanduser().resolve()
    needle = sys.argv[2]
    outdir = pathlib.Path(sys.argv[3]).expanduser() if len(sys.argv) > 3 else root.parent
    outdir.mkdir(parents=True, exist_ok=True)

    if not root.exists():
        sys.exit(f"export root not found: {root}")

    dirs = find_thread_dirs(root, needle)
    if not dirs:
        sys.exit(
            f"no thread directory matching {needle!r} under {root}\n"
            "Check the export finished unzipping and contains messages/inbox/."
        )
    if len(dirs) > 1:
        print(f"note: {len(dirs)} matching threads, using all", file=sys.stderr)

    rows, participants, title = [], [], None
    for d in dirs:
        msgs, parts, t = load_messages(d)
        title = title or t
        for p in parts:
            if p not in participants:
                participants.append(p)
        rows.extend(normalise(m, d, root) for m in msgs)

    # Export lists newest first; we want reading order.
    rows.sort(key=lambda r: r["ts_ms"] or 0)

    slug = needle.lower().replace(" ", "-").replace(".", "-")
    (outdir / f"{slug}.messages.json").write_text(
        json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8"
    )

    lines = []
    for r in rows:
        stamp = (r["ts"] or "")[:16].replace("T", " ")
        body = r["content"]
        if r["audio"]:
            body = (body + " " if body else "") + f"[VOICE {len(r['audio'])}: " + "; ".join(r["audio"]) + "]"
        if r["photos"]:
            body = (body + " " if body else "") + f"[{len(r['photos'])} photo]"
        if r["share"]:
            body = (body + " " if body else "") + f"[link {r['share']}]"
        if r["reactions"]:
            body += "  (" + ", ".join(r["reactions"]) + ")"
        lines.append(f"[{stamp}] {r['sender']}: {body}")
    (outdir / f"{slug}.transcript.txt").write_text("\n".join(lines), encoding="utf-8")

    audio = [(r["ts"], r["sender"], p) for r in rows for p in r["audio"]]
    (outdir / f"{slug}.audio.txt").write_text(
        "\n".join(f"{t}\t{s}\t{p}" for t, s, p in audio), encoding="utf-8"
    )

    per_sender = {}
    for r in rows:
        per_sender[r["sender"]] = per_sender.get(r["sender"], 0) + 1

    print(f"thread   : {title}")
    print(f"people   : {', '.join(participants)}")
    print(f"messages : {len(rows)}")
    for s, n in sorted(per_sender.items(), key=lambda kv: -kv[1]):
        print(f"           {n:>6}  {s}")
    if rows:
        print(f"range    : {rows[0]['ts']}  ..  {rows[-1]['ts']}")
    print(f"voice    : {len(audio)}")
    for t, s, p in audio:
        print(f"           {(t or '')[:16]}  {s}  {pathlib.Path(p).name}  {'OK' if pathlib.Path(p).exists() else 'MISSING'}")
    print(f"written  : {outdir}/{slug}.transcript.txt")


if __name__ == "__main__":
    main()
