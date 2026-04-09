# youtube-transcript

Fetch transcript from YouTube videos

## Usage

`/youtube-transcript <youtube_url>`

## What it does

1. Downloads YouTube video transcript using yt-dlp
2. Extracts and cleans the text from VTT format
3. Returns clean, readable transcript text

## Requirements

- `yt-dlp` must be installed (`brew install yt-dlp`)

## Implementation

```bash
#!/bin/bash
# Fetch and clean YouTube transcript

URL="$1"

if [ -z "$URL" ]; then
    echo "Error: Please provide a YouTube URL"
    exit 1
fi

# Extract video ID from URL
VIDEO_ID=$(echo "$URL" | sed -n 's/.*[?&]v=\([^&]*\).*/\1/p')
if [ -z "$VIDEO_ID" ]; then
    VIDEO_ID=$(echo "$URL" | sed -n 's/.*youtu\.be\/\([^?]*\).*/\1/p')
fi

if [ -z "$VIDEO_ID" ]; then
    echo "Error: Could not extract video ID from URL"
    exit 1
fi

# Create temp directory
TEMP_DIR="/tmp/yt-transcript-$$"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Download transcript
echo "Fetching transcript for video: $VIDEO_ID..." >&2
yt-dlp --write-auto-sub --sub-lang en --skip-download --sub-format vtt -o "transcript" "$URL" 2>&1 | grep -v "Downloading" >&2

# Check if transcript was downloaded
if [ ! -f "transcript.en.vtt" ]; then
    echo "Error: No English transcript available for this video" >&2
    cd /
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Clean and extract transcript text
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
' "transcript.en.vtt"

# Cleanup
cd /
rm -rf "$TEMP_DIR"
```

## Output

Returns the full transcript as continuous text, suitable for:
- Summarization
- Analysis
- Content extraction
- Note-taking

## Example

```bash
/youtube-transcript https://www.youtube.com/watch?v=wL-UOhZrc40
```

Returns the full transcript of the video for further processing.
