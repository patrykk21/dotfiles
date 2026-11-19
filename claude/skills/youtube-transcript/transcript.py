"""Print a YouTube video's captions as chaptered, timestamped Markdown.

Usage: python3 -I transcript.py <youtube-url>
"""

import json
import re
import shutil
import subprocess
import sys
import tempfile
from collections.abc import Iterator
from pathlib import Path
from typing import Any

SOUND_TAGS = re.compile(r"\s*\[(music|applause|laughter)\]\s*", re.I)
PARAGRAPH_SECONDS = 45


def yt_dlp(*args: str) -> str:
    result = subprocess.run(
        ["yt-dlp", "--no-update", "--no-warnings", *args],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        sys.exit(f"yt-dlp failed: {result.stderr.strip()}")
    return result.stdout


def pick_track(info: dict[str, Any]) -> tuple[str | None, bool, str]:
    manual = info.get("subtitles") or {}
    auto = info.get("automatic_captions") or {}
    english_manual = next((k for k in manual if k == "en" or k.startswith("en-")), None)
    if english_manual:
        return english_manual, False, "manual captions"
    if "en-orig" in auto:
        return "en-orig", True, "auto-generated captions (original English)"
    original = next((k for k in auto if k.endswith("-orig")), None)
    if "en" in auto:
        label = (
            f"auto-generated captions, machine-translated from {original[:-5]}"
            if original
            else "auto-generated captions"
        )
        return "en", True, label
    if original:
        return (
            original,
            True,
            f"auto-generated captions ({original[:-5]}, untranslated)",
        )
    return None, False, ""


def words(captions: dict[str, Any]) -> Iterator[tuple[float, str]]:
    # json3 splits a line into word segments; only the first segment of a line lacks its leading space.
    for event in captions.get("events", []):
        start_ms = event.get("tStartMs", 0)
        for i, seg in enumerate(event.get("segs") or []):
            text = seg.get("utf8", "").replace("\n", " ")
            if text.strip():
                yield (
                    (start_ms + seg.get("tOffsetMs", 0)) / 1000,
                    (" " if i == 0 else "") + text,
                )


def stamp(seconds: float) -> str:
    s = int(seconds)
    return (
        f"{s // 3600}:{s // 60 % 60:02d}:{s % 60:02d}"
        if s >= 3600
        else f"{s // 60:02d}:{s % 60:02d}"
    )


def render(info: dict[str, Any], captions: dict[str, Any], source: str) -> str:
    date = info.get("upload_date") or ""
    date = f"{date[:4]}-{date[4:6]}-{date[6:]}" if len(date) == 8 else date
    out = [
        f"# {info.get('title', '')}\n",
        f"{info.get('channel', '')} · {info.get('duration_string', '')} · published {date} · {info.get('webpage_url', '')}\n",
        f"Source: {source}. Sound tags removed; wording otherwise verbatim.\n",
    ]
    chapters = [(c["start_time"], c["title"]) for c in info.get("chapters") or []]
    buf: list[str] = []
    start, next_chapter = 0.0, 0

    def flush() -> None:
        text = re.sub(r"\s+", " ", SOUND_TAGS.sub(" ", "".join(buf))).strip()
        if text:
            out.append(f"[{stamp(start)}] {text}\n")
        buf.clear()

    for t, w in words(captions):
        sentence_ended = not buf or SOUND_TAGS.sub("", buf[-1]).rstrip().endswith(
            (".", "?", "!")
        )
        # Chapter times are approximate; wait for a sentence end so a sentence isn't split across headings.
        if (
            next_chapter < len(chapters)
            and t >= chapters[next_chapter][0] - 4
            and (sentence_ended or t > chapters[next_chapter][0] + 8)
        ):
            flush()
            out.append(f"## {chapters[next_chapter][1]}\n")
            next_chapter += 1
        elif buf and t - start > PARAGRAPH_SECONDS and sentence_ended:
            flush()
        if not buf:
            start = t
        buf.append(w)
    flush()
    return "\n".join(out)


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage: transcript.py <youtube-url>")
    if not shutil.which("yt-dlp"):
        sys.exit("yt-dlp is not installed (brew install yt-dlp)")
    url = sys.argv[1]
    info = json.loads(yt_dlp("-J", "--skip-download", url))
    lang, is_auto, source = pick_track(info)
    if not lang:
        sys.exit(
            "No captions available for this video. Transcribing the audio needs a speech-to-text tool such as whisper."
        )
    with tempfile.TemporaryDirectory() as tmp:
        yt_dlp(
            "--skip-download",
            "--write-auto-subs" if is_auto else "--write-subs",
            "--sub-langs",
            lang,
            "--sub-format",
            "json3",
            "-o",
            f"{tmp}/v",
            url,
        )
        files = list(Path(tmp).glob("v.*.json3"))
        if not files:
            sys.exit(f"yt-dlp did not save the {lang} caption track")
        captions = json.loads(files[0].read_text())
    print(render(info, captions, source))


if __name__ == "__main__":
    main()
