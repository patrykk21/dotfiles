---
name: youtube-transcript
description: Fetch a YouTube video's full transcript from its captions as chaptered, timestamped Markdown. Use when the user shares a YouTube link and wants it transcribed, summarized, or learned from.
---

# youtube-transcript

Run the bundled script with the video URL and save the output to a file in the scratchpad directory, named after the video ID:

```bash
python3 -I ~/.claude/skills/youtube-transcript/transcript.py "<youtube-url>" > "<scratchpad>/transcript-<video-id>.md"
```

Then read that file.

The script picks the best caption track in this order: manual English, auto-generated original English, auto-generated English (machine-translated), then the original-language auto track. It removes sound tags such as [music], splits the text into ~45-second paragraphs, and starts a new section at each chapter from the video description. The header says which track was used, so pass that on when the transcript came from auto-captions.

If the script reports no captions, say so. Transcribing the audio needs a speech-to-text tool such as whisper.

Requires `yt-dlp` (`brew install yt-dlp`).
