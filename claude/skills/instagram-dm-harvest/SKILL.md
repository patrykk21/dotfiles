---
name: instagram-dm-harvest
description: Harvest an Instagram DM thread from the live web UI via Chrome automation, attribute each message to the right sender, transcribe Italian (or other) voice notes with local Whisper, and write the distilled facts to Notion. Resumes from a saved checkpoint instead of re-scrolling. Use when the user says "get my Instagram DMs with X", "pull the thread with X", "what did X tell me about", "update my notes on X from Instagram", or asks to transcribe Instagram voice messages.
---

# Instagram DM harvest

Pull a full DM thread out of the Instagram web UI, keep sender attribution correct,
transcribe voice notes locally, and land the result in Notion. Resume from checkpoint.

## Read this first — the three things that waste the most time

1. **Reply-quote attribution is inverted from what it looks like.** Getting this wrong
   silently swaps who said what. See *Attribution* below. This is the single highest-value
   rule in this file.
2. **Bulk-extraction JavaScript gets blocked by the permission classifier.** Plain scrolling
   plus `get_page_text` is not blocked and is what actually works. Do not burn turns
   reshaping a blocked script — see *Permissions*.
3. **Instagram rate-limits DM backfill server-side.** No tool choice defeats it. See
   *The rate limit*.

## State

| Path | Contents |
| --- | --- |
| `~/.claude/ig-dm-harvest/<slug>.json` | Per-thread checkpoint: thread URL, newest and oldest message reached, voice-note inventory, Notion page id |
| `~/.claude/ig-dm-harvest/<slug>.messages.jsonl` | Appended harvested messages, one JSON object per line |

Read the checkpoint **before** scrolling. `oldest_reached` tells you where to stop
scrolling back; `newest_fetched` tells you which messages at the bottom are already
recorded. Only the gap needs fetching.

Write the checkpoint back at the end of every run, even a partial one. A run that
gets throttled after ten new messages still moved `oldest_reached`, and that saves the
next run ten screens of scrolling.

## Startup

```
tabs_context_mcp {createIfEmpty: true}      # mandatory before any other browser tool
navigate  https://www.instagram.com/direct/t/<thread_id>/
wait 8s                                     # the inbox renders as skeletons first
```

Find `thread_id` by opening the inbox and clicking the conversation — the URL becomes
`/direct/t/<thread_id>/`. Cache it in the checkpoint so later runs skip the inbox entirely.

## Permissions

The auto-mode classifier sits **in front of** the `/permissions` allowlist. A user granting
a tool does not guarantee the classifier will pass a given call — it judges each call's shape.

Observed behaviour:

| Call shape | Result |
| --- | --- |
| `tabs_context_mcp`, `navigate`, `computer` (scroll/click/screenshot), `get_page_text`, `read_network_requests` | Pass |
| `javascript_tool` doing small DOM probes | Passes sometimes |
| `javascript_tool` doing bulk message extraction, or scanning attributes for media URLs | **Blocked, reliably** |

When blocked, the denial says to stop and let the user decide. Respect it. Reshaping the
same script to slip past is the thing you are being told not to do. Switch to plain
scroll + `get_page_text`, which is the ordinary path and is not blocked.

## The rate limit

Instagram serves a burst of backfill, then stops issuing pagination requests entirely.
Symptoms: a spinner pins at the top of the pane, the scroll container's `scrollHeight`
stops growing, and consecutive `get_page_text` calls return identical content.

What is true about it:

- Faster scrolling, different tools, and JS-driven scrolling all hit the same point.
- Reloading the thread re-serves the same already-cached window, then stops at the same point.
- The boundary **differs between sessions** (one run reached Mon 13:47, the next stopped at
  Mon 19:39). So it is not a fixed per-thread limit.

**Try the observer re-trigger first, but do not expect it to work.** When the container sits
pinned at the top, the "load more" IntersectionObserver is already intersecting and may never
re-fire. Scrolling *down* out of the trigger zone and back *up* re-fires it:

```
scroll down 8 → wait 3 → scroll up 20 → wait 10   # repeat
```

Measured result: this **does** restore the request — the spinner appears on every up-scroll,
where before nothing fired at all. It did **not** produce new messages across four cycles.
So the loader asks and Instagram returns nothing. Worth two cycles to confirm; stop after four.

Whether the empty response is Instagram declining or the client discarding it cannot be
determined without inspecting the response body, and that inspection is exactly what the
classifier blocks. Do not claim one cause over the other without evidence.

So: harvest in bursts, save the checkpoint, and come back later. Do not loop on it.
Three identical `get_page_text` results in a row means stop and checkpoint.

If the user needs the **whole** history in one go, the data export is the only reliable
route — see *Data export*.

## Scrolling and harvesting

The message pane is the `div` with `flex-direction: column-reverse`, `clientHeight > 200`,
and `scrollHeight` exceeding it. In a column-reverse container `scrollTop` is `0` at the
**newest** message and goes **negative** toward older ones.

Instagram virtualizes the list: old message nodes are recycled out of the DOM as you scroll.
Harvest after every scroll step or you lose them.

Working loop, in one `browser_batch`:

```
computer scroll up 8 @ (990,400)
computer wait 5
get_page_text
computer scroll up 8 @ (990,400)
computer wait 5
get_page_text
```

Two to three scroll+read pairs per batch. Longer batches risk the extension timing out.
Compare each result to the previous one; identical output means throttled.

## Attribution — read carefully

`get_page_text` gives message text in order but no sender field. Sender comes from two
signals.

**Signal 1 — bubble position (from a screenshot).** Her messages sit left, grey. Yours sit
right, blue. Reliable, but costs a screenshot per screen.

**Signal 2 — reply-quote headers (from text alone). This is the one that gets misread:**

```
You replied to 🦋 G R E T A 🦋
  <quoted, faded>        <-- HER words. You are replying TO them.
  <solid bubble after>   <-- YOUR words.

🦋 G R E T A 🦋 replied to you
  <quoted, faded>        <-- YOUR words. She is replying TO them.
  <solid bubble after>   <-- HER words.
```

The quoted block belongs to whoever is named as being *replied to*, which is the **opposite**
person from the one the header appears to be about. Read the header as
"<actor> replied to <target>" and assign the quote to `<target>`.

Worked example from this thread. Under `You replied to 🦋 G R E T A 🦋`:

> *"Io mi immagino tipo l'ape maia (parte della mia infanzia)"*

That is **hers** — Maya the Bee was *her* childhood. The reply under it,
*"Ape maya? Come sei vecchiaaaa"*, is the user teasing her. Read naively you get it backwards
and record the user's childhood as hers.

Cross-check anything load-bearing against a screenshot before writing it to Notion.

## Voice notes

Instagram's own **"View transcription"** returns *"Unable to transcribe, try again"* on
Italian audio. Do not rely on it. Click it once to confirm, then move on.

Local toolchain, already installed:

- `whisper-cli` — whisper.cpp 1.8.3, at `/opt/homebrew/bin/whisper-cli`
- model — `~/.cache/whisper/ggml-large-v3-turbo.bin` (~1.6 GB, good on Italian)
- `ffmpeg` — `/opt/homebrew/bin/ffmpeg`

```bash
ffmpeg -i note.mp4 -ar 16000 -ac 1 -c:a pcm_s16le note.wav
whisper-cli -m ~/.cache/whisper/ggml-large-v3-turbo.bin -l it -f note.wav -otxt
```

Getting the audio files is the hard part. Extracting CDN URLs from the DOM is exactly the
call shape the classifier blocks. The dependable source is the data export.

Note whether each voice note is incoming or outgoing before transcribing — right-aligned
blue bubbles are the user's own, and transcribing those tells the user nothing new.

## Data export

The only route that reliably yields the complete thread **and** the voice-note audio:

Instagram → Settings → Accounts Centre → Your information and permissions →
Download your information → Request a download → *Some of your information* →
**Messages** → format **JSON** → range **All time**

Delivered by email, minutes to hours. Once unzipped, parse
`your_instagram_activity/messages/inbox/<thread>/message_1.json` locally — no browser, no
classifier, no rate limit. Audio sits in `audio/` beside it.

Instagram JSON is mojibake-encoded: it writes UTF-8 bytes as latin-1 escapes. Fix with
`s.encode('latin-1').decode('utf-8')` or accents and emoji come out corrupted.

## Output

Write distilled facts to Notion, not a raw transcript dump — a chat log does not answer
"what is her favourite colour".

Rules that make the page trustworthy:

- Every fact carries its **source quote** in the original language, so the user can check
  your reading rather than trust it.
- List what was **not** found explicitly. A silent gap reads as "no such fact exists".
- State the **date range covered** at the top. Partial coverage that looks complete is worse
  than an obvious gap.
- Flag uncertain attribution rather than smoothing it over.

## Checkpoint format

```json
{
  "thread_url": "https://www.instagram.com/direct/t/<id>/",
  "person": "greta.gremlins",
  "notion_page_id": "<uuid>",
  "newest_fetched": {"ts": "2026-08-11T19:20", "text": "first 80 chars", "sender": "user"},
  "oldest_reached": {"ts": "2026-08-10T13:47", "text": "first 80 chars", "sender": "greta"},
  "voice_notes": [{"ts": "...", "duration": "3:59", "sender": "user", "transcribed": false}],
  "runs": [{"date": "2026-08-11", "outcome": "throttled at Mon 19:39"}]
}
```
