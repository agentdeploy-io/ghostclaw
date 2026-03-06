#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env}"

DEFAULT_TEXT=$'Careful now... clickin'\'' random buttons is how lads end up buyin'\'' Dogecoin at the top."\n\n"Easy there tiger. Let Lippy show ya where the gold is....\n\nmake sure to check out the potline, it'\''s great crack'
TEXT="$DEFAULT_TEXT"
OUTPUT_PATH=""
USE_REFERENCE=1

usage() {
  cat <<'EOF'
Usage: ./scripts/fish-tts-mp3.sh [options]

Options:
  --text "..."        Override default text
  --output PATH       Output MP3 path (default: ./data/artifacts/fish-tts-<timestamp>.mp3)
  --no-reference      Do not send MENTOR_FISH_REFERENCE_ID
  -h, --help          Show help
EOF
}

json_escape() {
  local raw="$1"
  raw="${raw//\\/\\\\}"
  raw="${raw//\"/\\\"}"
  raw="${raw//$'\n'/\\n}"
  printf '%s' "$raw"
}

env_get() {
  local key="$1"
  awk -v k="$key" 'index($0, k"=") == 1 {print substr($0, length(k)+2); exit}' "$ENV_FILE"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --text)
      TEXT="${2:?missing value}"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="${2:?missing value}"
      shift 2
      ;;
    --no-reference)
      USE_REFERENCE=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: env file not found: $ENV_FILE" >&2
  exit 1
fi

FISH_TTS_ENDPOINT="$(env_get "MENTOR_FISH_TTS_ENDPOINT")"
FISH_API_KEY="$(env_get "MENTOR_FISH_API_KEY")"
FISH_MODEL="$(env_get "MENTOR_FISH_MODEL")"
FISH_REFERENCE_ID="$(env_get "MENTOR_FISH_REFERENCE_ID")"
FISH_FORMAT="$(env_get "MENTOR_FISH_FORMAT")"
FISH_LATENCY="$(env_get "MENTOR_FISH_LATENCY")"
FISH_NORMALIZE="$(env_get "MENTOR_FISH_NORMALIZE")"
FISH_TEMPERATURE="$(env_get "MENTOR_FISH_TEMPERATURE")"
FISH_TOP_P="$(env_get "MENTOR_FISH_TOP_P")"
FISH_REPETITION_PENALTY="$(env_get "MENTOR_FISH_REPETITION_PENALTY")"
FISH_MAX_NEW_TOKENS="$(env_get "MENTOR_FISH_MAX_NEW_TOKENS")"
FISH_CHUNK_LENGTH="$(env_get "MENTOR_FISH_CHUNK_LENGTH")"

if [[ -z "$FISH_TTS_ENDPOINT" || -z "$FISH_API_KEY" || -z "$FISH_MODEL" ]]; then
  echo "ERROR: need MENTOR_FISH_TTS_ENDPOINT, MENTOR_FISH_API_KEY, and MENTOR_FISH_MODEL in $ENV_FILE" >&2
  exit 1
fi

if [[ -z "$FISH_FORMAT" ]]; then
  FISH_FORMAT="mp3"
fi
if [[ -z "$FISH_LATENCY" ]]; then
  FISH_LATENCY="normal"
fi
if [[ -z "$FISH_NORMALIZE" ]]; then
  FISH_NORMALIZE="true"
fi
if [[ -z "$FISH_TEMPERATURE" ]]; then
  FISH_TEMPERATURE="0.7"
fi
if [[ -z "$FISH_TOP_P" ]]; then
  FISH_TOP_P="0.7"
fi
if [[ -z "$FISH_REPETITION_PENALTY" ]]; then
  FISH_REPETITION_PENALTY="1.2"
fi
if [[ -z "$FISH_MAX_NEW_TOKENS" ]]; then
  FISH_MAX_NEW_TOKENS="1024"
fi
if [[ -z "$FISH_CHUNK_LENGTH" ]]; then
  FISH_CHUNK_LENGTH="240"
fi

if [[ -z "$OUTPUT_PATH" ]]; then
  mkdir -p "$REPO_ROOT/data/artifacts"
  OUTPUT_PATH="$REPO_ROOT/data/artifacts/fish-tts-$(date -u +%Y%m%dT%H%M%SZ).mp3"
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

PAYLOAD='{
  "text": "'"$(json_escape "$TEXT")"'",
  "format": "mp3",
  "normalize": '"$FISH_NORMALIZE"',
  "latency": "'"$(json_escape "$FISH_LATENCY")"'",
  "temperature": '"$FISH_TEMPERATURE"',
  "top_p": '"$FISH_TOP_P"',
  "repetition_penalty": '"$FISH_REPETITION_PENALTY"',
  "max_new_tokens": '"$FISH_MAX_NEW_TOKENS"',
  "chunk_length": '"$FISH_CHUNK_LENGTH"'
}'

if [[ "$USE_REFERENCE" -eq 1 && -n "$FISH_REFERENCE_ID" ]]; then
  PAYLOAD="${PAYLOAD%?},\"reference_id\":\"$(json_escape "$FISH_REFERENCE_ID")\"}"
fi

HEADERS_FILE="$(mktemp)"
BODY_FILE="$(mktemp)"
trap 'rm -f "$HEADERS_FILE" "$BODY_FILE"' EXIT

HTTP_CODE="$(
  curl -sS \
    -D "$HEADERS_FILE" \
    -o "$BODY_FILE" \
    -w '%{http_code}' \
    -X POST "$FISH_TTS_ENDPOINT" \
    -H "Authorization: Bearer $FISH_API_KEY" \
    -H "Content-Type: application/json" \
    -H "model: $FISH_MODEL" \
    -d "$PAYLOAD"
)"

if [[ "$HTTP_CODE" != 2* ]]; then
  echo "ERROR: Fish TTS request failed with HTTP $HTTP_CODE" >&2
  head -c 500 "$BODY_FILE" >&2 || true
  exit 1
fi

cp "$BODY_FILE" "$OUTPUT_PATH"
FILE_SIZE="$(wc -c < "$OUTPUT_PATH" | tr -d ' ')"

echo "ok"
echo "output=$OUTPUT_PATH"
echo "bytes=$FILE_SIZE"
echo "provider=fish"
echo "model=$FISH_MODEL"
