#!/usr/bin/env bash
# Test OpenAI Whisper API (transcription).
# Usage:
#   OPENAI_API_KEY=sk-... ./scripts/test-whisper-api.sh
#   OPENAI_API_KEY=sk-... ./scripts/test-whisper-api.sh /path/to/audio.m4a

set -e
API_KEY="${OPENAI_API_KEY:-}"
AUDIO_FILE="${1:-}"

if [[ -z "$API_KEY" ]]; then
  echo "Set OPENAI_API_KEY to your OpenAI API key."
  echo "Example: OPENAI_API_KEY=sk-... ./scripts/test-whisper-api.sh [audio_file]"
  exit 1
fi

# If no file given, create a short silent WAV with Python so we can still test the endpoint
if [[ -z "$AUDIO_FILE" || ! -f "$AUDIO_FILE" ]]; then
  echo "No audio file provided or file not found. Creating 1s silent WAV for endpoint test..."
  AUDIO_FILE=$(mktemp -t whisper-test-XXXXXX.wav)
  trap "rm -f $AUDIO_FILE" EXIT
  python3 -c "
import wave, struct, math
sr = 16000
n = sr  # 1 second
with wave.open('$AUDIO_FILE', 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(sr)
    for i in range(n):
        # very quiet tone so it's not completely empty
        v = int(100 * math.sin(2 * math.pi * 440 * i / sr))
        w.writeframes(struct.pack('<h', v))
"
  echo "Created $AUDIO_FILE"
fi

echo "Calling Whisper API (model=whisper-1)..."
RESP=$(curl -s -w "\n%{http_code}" -X POST "https://api.openai.com/v1/audio/transcriptions" \
  -H "Authorization: Bearer $API_KEY" \
  -F "file=@$AUDIO_FILE" \
  -F "model=whisper-1")

# macOS-compatible: last line is status code
HTTP_CODE=$(echo "$RESP" | tail -1)
HTTP_BODY=$(echo "$RESP" | sed '$d')

echo "HTTP status: $HTTP_CODE"
echo "Response:"
echo "$HTTP_BODY" | python3 -m json.tool 2>/dev/null || echo "$HTTP_BODY"

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
  echo ""
  echo "Whisper API call succeeded."
else
  echo ""
  echo "Whisper API returned an error."
  exit 1
fi
