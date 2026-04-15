# fact-check

Fact-check a YouTube video by extracting its transcript, summarizing key claims, and validating them against research. Outputs a human-readable summary directly in chat — no Notion, no databases.

## Usage

`/fact-check <youtube_url>`

## What it does

1. Extracts video metadata and transcript (reuses yt-dlp technique from `/youtube-transcript`)
2. Identifies the key claims and ideas from the transcript
3. Researches each claim against peer-reviewed sources using WebSearch
4. Prints a human-readable summary directly in chat

## Output Format

**Write it like a short blog post** — conversational, easy to read, no tables with "CONFIRMED/UNCONFIRMED" verdicts. The reader just wants to know: is this video worth my time, and can I trust what it says?

Structure:

```
## [Video Title]
**[Channel]** | [Duration] | [Date]

### What This Video Is About
[2-3 sentence overview of the video's core message and who it's for]

### The Key Ideas
[Walk through the main points naturally, as if explaining to a friend. Use the speaker's examples where they're good.]

### What The Research Actually Says
[For each major claim, weave in what research supports or contradicts it. Name the researchers/studies naturally in prose — not as citations in a table. Be specific about what's solid and what's shaky.]

### The Fishy Parts
[Call out anything that's wrong, oversimplified, or unsupported. Explain WHY it's off, not just that it is. If something is presented as fact but is actually just one person's framework or a pop-psychology claim, say so.]

### Bottom Line
[1-2 sentences: Is this video worth watching? What should the viewer take away vs take with a grain of salt?]
```

**Tone guidelines:**
- Write like you're telling a friend about a video you watched and looked into
- No academic jargon, no verdict tables, no "CONFIRMED/PARTIALLY CONFIRMED" labels
- Name-drop researchers naturally: "Gottman's research actually shows..." not "Source: Gottman (1992)"
- Be direct about what's BS: "This sounds good but there's no research behind it" 
- Be equally direct about what's solid: "This is actually well-supported — Pinker's 2008 paper covers exactly this"
- Keep it concise — aim for something you'd read in 2-3 minutes

## Implementation

### Step 1: Extract video metadata
```bash
yt-dlp --print title --print channel --print upload_date --print duration_string "$URL" 2>/dev/null
```

### Step 2: Extract transcript
```bash
# Create temp directory for this video
TEMP_DIR="/tmp/yt-transcript-$$"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Download subtitles
yt-dlp --write-auto-sub --sub-lang en --skip-download --sub-format vtt -o "transcript" "$URL" 2>&1

# Clean VTT to plain text
awk '
BEGIN { prev = "" }
/^WEBVTT/ { next }
/^Kind:/ { next }
/^Language:/ { next }
/^$/ { next }
/^[0-9][0-9]:/ { next }
/align:start/ { next }
{
    gsub(/<[^>]*>/, "")
    gsub(/^[ \t]+/, "")
    gsub(/[ \t]+$/, "")
    if (length($0) == 0) next
    if ($0 == prev) next
    printf "%s ", $0
    prev = $0
}
' transcript.en.vtt

# Cleanup
cd /
rm -rf "$TEMP_DIR"
```

### Step 3: Analyze transcript
- Read through the transcript and identify the 3-7 main claims or ideas
- Note which claims are attributed to specific people/research vs presented as original insight

### Step 4: Research claims
- Use WebSearch to find peer-reviewed sources for each major claim
- Search for BOTH supporting and contradicting evidence
- Focus on: original studies, meta-analyses, established psychology/science frameworks
- Don't just search for confirmation — actively look for "criticism of X" or "X debunked"

### Step 5: Write the summary
- Follow the output format above
- Print directly to chat — do NOT create any Notion entries, files, or external artifacts
- Keep it readable and concise

## Important Rules

- **NO Notion entries** — this command only prints to chat
- **NO tables with verdicts** — write prose, not scorecards
- **NO academic citation format** — weave sources naturally into the text
- **Be honest** — if the video is mostly BS, say so. If it's solid, say so.
- **Use the team-with-judge pattern** for thorough research when the video makes many claims (spawn researchers + judge). For short/simple videos, just do the research inline.
