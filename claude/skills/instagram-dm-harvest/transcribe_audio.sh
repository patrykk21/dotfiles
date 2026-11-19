#!/usr/bin/env bash
# Transcribe Instagram voice notes listed by parse_export.py.
#   ./transcribe_audio.sh <slug>.audio.txt [lang] [outdir]
# Input columns: timestamp <TAB> sender <TAB> path
set -uo pipefail

LIST="${1:?usage: transcribe_audio.sh <audio.txt> [lang] [outdir]}"
LANG_CODE="${2:-it}"
OUT="${3:-$(dirname "$LIST")/transcripts}"
MODEL="$HOME/.cache/whisper/ggml-large-v3-turbo.bin"

command -v ffmpeg     >/dev/null || { echo "ffmpeg missing"; exit 1; }
command -v whisper-cli >/dev/null || { echo "whisper-cli missing"; exit 1; }
[ -f "$MODEL" ] || { echo "model missing: $MODEL"; exit 1; }

mkdir -p "$OUT"
ok=0; fail=0; n=0

while IFS=$'\t' read -r ts sender path; do
  [ -z "${path:-}" ] && continue
  n=$((n+1))
  if [ ! -f "$path" ]; then
    echo "[$n] MISSING $path"; fail=$((fail+1)); continue
  fi

  # Timestamp first so transcripts sort chronologically.
  safe_ts=$(printf '%s' "${ts:-unknown}" | tr -c 'A-Za-z0-9' '-' | cut -c1-16)
  safe_sender=$(printf '%s' "${sender:-unknown}" | tr -c 'A-Za-z0-9' '-' | cut -c1-20)
  base="$OUT/${safe_ts}_${safe_sender}_$(basename "${path%.*}")"

  if ! ffmpeg -nostdin -loglevel error -y -i "$path" \
        -ar 16000 -ac 1 -c:a pcm_s16le "$base.wav" 2>"$base.ffmpeg.err"; then
    echo "[$n] FFMPEG FAIL $(basename "$path") — see $base.ffmpeg.err"
    fail=$((fail+1)); continue
  fi
  rm -f "$base.ffmpeg.err"

  if whisper-cli -m "$MODEL" -l "$LANG_CODE" -f "$base.wav" -otxt -of "$base" \
       >"$base.log" 2>&1; then
    rm -f "$base.wav"
    echo "[$n] OK ${ts:-?} ${sender:-?}"
    [ -f "$base.txt" ] && sed 's/^/      /' "$base.txt"
    ok=$((ok+1))
  else
    echo "[$n] WHISPER FAIL $(basename "$path") — see $base.log"
    fail=$((fail+1))
  fi
done < <(cat "$LIST"; echo)   # trailing newline: bare `read` drops a final unterminated line

echo
echo "transcribed $ok/$n  (failed $fail)"
echo "output: $OUT"
