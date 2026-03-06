#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_ROOT/.env}"

PROMPT="${PROMPT:-A sharp, cinematic gold-claw mascot in a pub, high detail}"
IMAGE_TIMEOUT="${IMAGE_TIMEOUT:-120}"
VIDEO_TIMEOUT="${VIDEO_TIMEOUT:-240}"
RUN_STANDALONE_MENTOR=1

usage() {
  cat <<'EOF'
Usage: ./scripts/test-media-providers.sh [options]

Options:
  --prompt "..."           Override prompt
  --no-standalone-mentor   Skip local mentor-mcp tool probes
  -h, --help               Show help
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

load_env_file() {
  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    [[ -z "$key" || "$key" == "$line" ]] && continue
    export "$key=$value"
  done < "$ENV_FILE"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt)
      PROMPT="${2:?missing value}"
      shift 2
      ;;
    --no-standalone-mentor)
      RUN_STANDALONE_MENTOR=0
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

run_json_probe() {
  local label="$1"
  local timeout="$2"
  local url="$3"
  local auth_token="$4"
  local extra_header_name="$5"
  local extra_header_value="$6"
  local payload="$7"

  local headers_file body_file http_code content_type body_preview
  headers_file="$(mktemp)"
  body_file="$(mktemp)"

  if [[ -n "$extra_header_name" ]]; then
    http_code="$(
      curl -sS \
        -D "$headers_file" \
        -o "$body_file" \
        --connect-timeout 10 \
        --max-time "$timeout" \
        -w '%{http_code}' \
        -X POST "$url" \
        -H "Authorization: Bearer $auth_token" \
        -H "Content-Type: application/json" \
        -H "$extra_header_name: $extra_header_value" \
        -d "$payload"
    )"
  else
    http_code="$(
      curl -sS \
        -D "$headers_file" \
        -o "$body_file" \
        --connect-timeout 10 \
        --max-time "$timeout" \
        -w '%{http_code}' \
        -X POST "$url" \
        -H "Authorization: Bearer $auth_token" \
        -H "Content-Type: application/json" \
        -d "$payload"
    )"
  fi

  content_type="$(awk 'BEGIN{IGNORECASE=1} /^content-type:/ {sub(/\r$/,"",$2); print $2; exit}' "$headers_file")"
  body_preview="$(head -c 220 "$body_file" | tr '\n' ' ')"

  if [[ "$http_code" == 2* ]]; then
    echo "PASS|$label|http=$http_code|content_type=${content_type:-unknown}|$body_preview"
  else
    echo "FAIL|$label|http=$http_code|content_type=${content_type:-unknown}|$body_preview"
  fi

  rm -f "$headers_file" "$body_file"
}

run_standalone_mentor_probe() {
  local label="$1"
  local tool_name="$2"
  local payload="$3"
  local temp_dir pid_file log_file response

  temp_dir="$(mktemp -d)"
  pid_file="$(mktemp)"
  log_file="$(mktemp)"

  cp "$REPO_ROOT/../lippyclaw/mentor-mcp/package.json" "$temp_dir/package.json"
  cp "$REPO_ROOT/../lippyclaw/mentor-mcp/server.mjs" "$temp_dir/server.mjs"
  mkdir -p "$temp_dir/out"

  (
    cd "$temp_dir"
    npm install --omit=dev --silent >/dev/null 2>&1
    load_env_file
    export MENTOR_ARTIFACT_DIR="$temp_dir/out"
    export MENTOR_IMAGE_ARTIFACT_DIR="$temp_dir/out"
    export MENTOR_VIDEO_ARTIFACT_DIR="$temp_dir/out"
    export MENTOR_MEMORY_FILE="$temp_dir/out/memory.json"
    export MENTOR_VOICE_CONTEXT_PATH="$temp_dir/out/voice_context.txt"
    export MENTOR_VOICE_SAMPLE_PATH="$temp_dir/out/master-voice.wav"
    export MENTOR_PERSONA_FILE="$REPO_ROOT/mentor/persona.md"
    MENTOR_MCP_PORT=8899 node server.mjs >"$log_file" 2>&1 &
    echo $! >"$pid_file"
  )

  sleep 2

  response="$(
    curl -sS \
      --connect-timeout 5 \
      --max-time "$VIDEO_TIMEOUT" \
      -X POST http://127.0.0.1:8899/mcp \
      -H 'content-type: application/json' \
      -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"$tool_name\",\"arguments\":$payload}}" \
      2>/dev/null || true
  )"

  if grep -q '"error"' <<<"$response"; then
    echo "FAIL|$label|mentor_error|$(printf '%s' "$response" | head -c 240)"
  elif [[ -n "$response" ]]; then
    echo "PASS|$label|mentor_ok|$(printf '%s' "$response" | head -c 240)"
  else
    echo "FAIL|$label|mentor_no_response|$(head -c 240 "$log_file" | tr '\n' ' ')"
  fi

  if [[ -s "$pid_file" ]]; then
    kill "$(cat "$pid_file")" >/dev/null 2>&1 || true
  fi
  rm -rf "$temp_dir" "$pid_file" "$log_file"
}

CHUTES_IMAGE_RUN_ENDPOINT="$(env_get "MENTOR_CHUTES_IMAGE_RUN_ENDPOINT")"
CHUTES_IMAGE_MODEL="$(env_get "MENTOR_CHUTES_IMAGE_MODEL")"
CHUTES_IMAGE_API_KEY="$(env_get "MENTOR_IMAGE_API_KEY")"
NOVITA_IMAGE_ENDPOINT="$(env_get "MENTOR_NOVITA_IMAGE_ENDPOINT")"
NOVITA_API_KEY="$(env_get "MENTOR_NOVITA_API_KEY")"
NOVITA_IMAGE_MODEL="$(env_get "MENTOR_NOVITA_IMAGE_MODEL")"
CHUTES_VIDEO_RUN_ENDPOINT="$(env_get "MENTOR_CHUTES_VIDEO_RUN_ENDPOINT")"
CHUTES_VIDEO_MODEL="$(env_get "MENTOR_CHUTES_VIDEO_MODEL")"
CHUTES_VIDEO_API_KEY="$(env_get "MENTOR_VIDEO_API_KEY")"
NOVITA_VIDEO_ENDPOINT="$(env_get "MENTOR_NOVITA_VIDEO_ENDPOINT")"
NOVITA_VIDEO_MODEL="$(env_get "MENTOR_NOVITA_VIDEO_MODEL")"

echo "[direct] provider probes"

if [[ -n "$CHUTES_IMAGE_RUN_ENDPOINT" && -n "$CHUTES_IMAGE_MODEL" && -n "$CHUTES_IMAGE_API_KEY" ]]; then
  run_json_probe \
    "chutes_image" \
    "$IMAGE_TIMEOUT" \
    "$CHUTES_IMAGE_RUN_ENDPOINT" \
    "$CHUTES_IMAGE_API_KEY" \
    "" \
    "" \
    "{\"model\":\"$CHUTES_IMAGE_MODEL\",\"input\":{\"prompt\":\"$(json_escape "$PROMPT")\",\"size\":\"1024x1024\",\"width\":1024,\"height\":1024,\"num_images\":1,\"response_format\":\"url\"}}"
else
  echo "SKIP|chutes_image|missing_env"
fi

if [[ -n "$NOVITA_IMAGE_ENDPOINT" && -n "$NOVITA_IMAGE_MODEL" && -n "$NOVITA_API_KEY" ]]; then
  run_json_probe \
    "novita_image" \
    "$IMAGE_TIMEOUT" \
    "$NOVITA_IMAGE_ENDPOINT" \
    "$NOVITA_API_KEY" \
    "" \
    "" \
    "{\"prompt\":\"$(json_escape "$PROMPT")\",\"model_name\":\"$NOVITA_IMAGE_MODEL\",\"width\":1024,\"height\":1024,\"size\":\"1024x1024\",\"response_format\":\"url\",\"num_images\":1}"
else
  echo "SKIP|novita_image|missing_env"
fi

if [[ -n "$CHUTES_VIDEO_RUN_ENDPOINT" && -n "$CHUTES_VIDEO_MODEL" && -n "$CHUTES_VIDEO_API_KEY" ]]; then
  run_json_probe \
    "chutes_video" \
    "$VIDEO_TIMEOUT" \
    "$CHUTES_VIDEO_RUN_ENDPOINT" \
    "$CHUTES_VIDEO_API_KEY" \
    "" \
    "" \
    "{\"model\":\"$CHUTES_VIDEO_MODEL\",\"input\":{\"prompt\":\"$(json_escape "$PROMPT")\",\"size\":\"1024x576\",\"width\":1024,\"height\":576,\"duration_seconds\":5}}"
else
  echo "SKIP|chutes_video|missing_env"
fi

if [[ -n "$NOVITA_VIDEO_ENDPOINT" && -n "$NOVITA_VIDEO_MODEL" && -n "$NOVITA_API_KEY" ]]; then
  run_json_probe \
    "novita_video" \
    "$VIDEO_TIMEOUT" \
    "$NOVITA_VIDEO_ENDPOINT" \
    "$NOVITA_API_KEY" \
    "" \
    "" \
    "{\"prompt\":\"$(json_escape "$PROMPT")\",\"model_name\":\"$NOVITA_VIDEO_MODEL\",\"width\":1024,\"height\":576,\"duration_seconds\":5}"
else
  echo "SKIP|novita_video|missing_env"
fi

if [[ "$RUN_STANDALONE_MENTOR" -eq 1 ]]; then
  echo "[mentor] standalone tool probes"
  run_standalone_mentor_probe \
    "mentor_image_tool_chutes" \
    "mentor.image" \
    "{\"prompt\":\"$(json_escape "$PROMPT")\",\"provider\":\"chutes\"}"
  run_standalone_mentor_probe \
    "mentor_image_tool_novita" \
    "mentor.image" \
    "{\"prompt\":\"$(json_escape "$PROMPT")\",\"provider\":\"novita\"}"
  run_standalone_mentor_probe \
    "mentor_video_tool_chutes" \
    "mentor.video" \
    "{\"prompt\":\"$(json_escape "$PROMPT")\",\"provider\":\"chutes\"}"
  run_standalone_mentor_probe \
    "mentor_video_tool_novita" \
    "mentor.video" \
    "{\"prompt\":\"$(json_escape "$PROMPT")\",\"provider\":\"novita\"}"
fi
