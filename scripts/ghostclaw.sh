#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"
LOG_DIR="$REPO_ROOT/data/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/ghostclaw-$(date -u +%Y%m%dT%H%M%SZ).log"
exec > >(tee -a "$LOG_FILE") 2>&1

log() {
  local level="$1"
  local message="$2"
  printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$message"
}

run_with_timeout() {
  local seconds="$1"
  shift

  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$seconds" "$@"
    return
  fi

  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
    return
  fi

  "$@"
}

on_error() {
  local line="$1"
  local rc="$2"
  local cmd="$3"
  log "ERROR" "line=$line rc=$rc cmd=$cmd"
  log "ERROR" "full log: $LOG_FILE"
  exit "$rc"
}

trap 'on_error "$LINENO" "$?" "$BASH_COMMAND"' ERR

compose_local() {
  docker compose --env-file "$ENV_FILE" \
    -f "$REPO_ROOT/docker-compose.yml" \
    -f "$REPO_ROOT/docker-compose.local.yml" "$@"
}

BUILDABLE_SERVICES=(
  "ironclaw"
  "camoufox-tool"
  "camoufox-mcp"
  "mentor-mcp"
  "voice-mcp"
  "agent-sandbox"
)

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: missing required command: $1" >&2
    exit 1
  fi
}

read_env_var() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k {print substr($0, index($0, "=") + 1)}' "$ENV_FILE" | tail -n 1
}

has_env_key() {
  local key="$1"
  awk -F= -v k="$key" '$1 == k {found=1} END {exit found?0:1}' "$ENV_FILE"
}

upsert_env_var() {
  local key="$1"
  local value="$2"

  if has_env_key "$key"; then
    local tmp_file
    tmp_file="$(mktemp "$REPO_ROOT/.env.tmp.XXXXXX")"
    awk -F= -v k="$key" -v v="$value" 'BEGIN{OFS="="} $1==k {$0=k"="v} {print}' "$ENV_FILE" > "$tmp_file"
    mv "$tmp_file" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

set_env_var_if_missing() {
  local key="$1"
  local value="$2"
  if ! has_env_key "$key"; then
    printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

is_placeholder_or_empty() {
  local value="$1"
  if [[ -z "$value" ]]; then
    return 0
  fi

  case "$value" in
    replace_with_*) return 0 ;;
    __CHANGE_ME__) return 0 ;;
    *) return 1 ;;
  esac
}

generate_secret_if_missing() {
  local key="$1"
  local bytes="$2"
  local current

  current="$(read_env_var "$key")"
  if is_placeholder_or_empty "$current"; then
    upsert_env_var "$key" "$(openssl rand -hex "$bytes")"
  fi
}

prompt_required_if_missing() {
  local key="$1"
  local prompt="$2"
  local secret="${3:-false}"
  local current

  current="$(read_env_var "$key")"
  if ! is_placeholder_or_empty "$current"; then
    return
  fi

  local input=""
  if [[ "$secret" == "true" ]]; then
    read -r -s -p "$prompt" input
    echo
  else
    read -r -p "$prompt" input
  fi

  if [[ -z "$input" ]]; then
    echo "ERROR: value required for $key" >&2
    exit 1
  fi

  upsert_env_var "$key" "$input"
}

ensure_env_file() {
  require_cmd awk
  require_cmd openssl
  require_cmd chmod

  if [[ ! -f "$ENV_FILE" ]]; then
    touch "$ENV_FILE"
  fi

  mkdir -p "$REPO_ROOT/data/mentor"
  mkdir -p "$REPO_ROOT/mentor"

  if [[ ! -f "$REPO_ROOT/mentor/persona.md" ]]; then
    cat > "$REPO_ROOT/mentor/persona.md" <<'PERSONA'
You are Ghostclaw Mentor.

Operating style:
- Be direct, calm, and execution-focused.
- Prioritize the next 1-3 commands/actions over long theory.
- If risk is high, state the risk and safe fallback.
- Keep answers concise but technically complete.

Scope:
- Help users operate and debug IronClaw + Camoufox production stacks.
- Default to practical runbook guidance.
PERSONA
  fi

  set_env_var_if_missing "IRONCLAW_GIT_URL" "replace_with_official_ironclaw_git_url"
  set_env_var_if_missing "IRONCLAW_GIT_REF" "replace_with_git_tag_or_commit"
  set_env_var_if_missing "LIPPYCLAW_GIT_URL" ""
  set_env_var_if_missing "LIPPYCLAW_GIT_REF" ""
  set_env_var_if_missing "POSTGRES_DB" "ironclaw"
  set_env_var_if_missing "POSTGRES_USER" "ironclaw"
  set_env_var_if_missing "POSTGRES_PASSWORD" "$(openssl rand -hex 32)"
  set_env_var_if_missing "INTERNAL_API_TOKEN" "$(openssl rand -hex 48)"
  set_env_var_if_missing "GATEWAY_AUTH_TOKEN" "$(openssl rand -hex 32)"

  set_env_var_if_missing "MAIN_LLM_BASE_URL" "https://llm.chutes.ai/v1"
  set_env_var_if_missing "MAIN_LLM_MODEL" "Qwen/Qwen3.5-397B-A17B-TEE"
  set_env_var_if_missing "MAIN_LLM_API_KEY" "replace_with_main_llm_api_key"
  set_env_var_if_missing "SUB_LLM_BASE_URL" "https://llm.chutes.ai/v1"
  set_env_var_if_missing "SUB_LLM_MODEL" "MiniMaxAI/MiniMax-M2.5-TEE"
  set_env_var_if_missing "SUB_LLM_API_KEY" "replace_with_sub_llm_api_key_or_same_as_main"

  set_env_var_if_missing "MENTOR_NAME" "Lippyclaw Mentor"
  set_env_var_if_missing "MENTOR_PERSONA_FILE" "/mentor/persona.md"
  set_env_var_if_missing "MENTOR_MEMORY_FILE" "/data/mentor/memory.json"
  set_env_var_if_missing "MENTOR_MEMORY_WINDOW" "14"
  set_env_var_if_missing "MENTOR_LLM_BASE_URL" "https://llm.chutes.ai/v1"
  set_env_var_if_missing "MENTOR_LLM_MODEL" "MiniMaxAI/MiniMax-M2.5-TEE"
  set_env_var_if_missing "MENTOR_LLM_API_KEY" "replace_with_mentor_llm_api_key_or_same_as_sub"
  set_env_var_if_missing "ENABLE_MENTOR_VOICE" "true"
  set_env_var_if_missing "MENTOR_AUTO_BOOTSTRAP_VOICE" "true"
  set_env_var_if_missing "MENTOR_VOICE_PROVIDER" "auto"
  set_env_var_if_missing "MENTOR_VOICE_API_BASE_URL" "https://llm.chutes.ai/v1"
  set_env_var_if_missing "MENTOR_VOICE_API_KEY" "replace_with_mentor_voice_api_key_or_same_as_main"
  set_env_var_if_missing "MENTOR_FISH_API_BASE_URL" "https://api.fish.audio"
  set_env_var_if_missing "MENTOR_FISH_API_KEY" "replace_with_fish_audio_api_key"
  set_env_var_if_missing "MENTOR_FISH_TTS_ENDPOINT" "https://api.fish.audio/v1/tts"
  set_env_var_if_missing "MENTOR_FISH_ASR_ENDPOINT" "https://api.fish.audio/v1/asr"
  set_env_var_if_missing "MENTOR_FISH_MODEL" "s1"
  set_env_var_if_missing "MENTOR_FISH_REFERENCE_ID" ""
  set_env_var_if_missing "MENTOR_FISH_FORMAT" "mp3"
  set_env_var_if_missing "MENTOR_FISH_LATENCY" "normal"
  set_env_var_if_missing "MENTOR_FISH_NORMALIZE" "true"
  set_env_var_if_missing "MENTOR_FISH_IGNORE_TIMESTAMPS" "true"
  set_env_var_if_missing "MENTOR_FISH_TEMPERATURE" "0.7"
  set_env_var_if_missing "MENTOR_FISH_TOP_P" "0.7"
  set_env_var_if_missing "MENTOR_FISH_REPETITION_PENALTY" "1.2"
  set_env_var_if_missing "MENTOR_FISH_MAX_NEW_TOKENS" "1024"
  set_env_var_if_missing "MENTOR_FISH_CHUNK_LENGTH" "240"
  set_env_var_if_missing "MENTOR_CHUTES_VOICE_MODE" "chutes_direct"
  set_env_var_if_missing "MENTOR_CHUTES_RUN_ENDPOINT" "https://llm.chutes.ai/v1/run"
  set_env_var_if_missing "MENTOR_CHUTES_WHISPER_MODEL" "openai/whisper-large-v3-turbo"
  set_env_var_if_missing "MENTOR_CHUTES_CSM_MODEL" "sesame/csm-1b"
  set_env_var_if_missing "MENTOR_CHUTES_KOKORO_MODEL" "hexgrad/Kokoro-82M"
  set_env_var_if_missing "MENTOR_CHUTES_WHISPER_ENDPOINT" "https://chutes-whisper-large-v3.chutes.ai/transcribe"
  set_env_var_if_missing "MENTOR_CHUTES_CSM_ENDPOINT" "https://chutes-csm-1b.chutes.ai/speak"
  set_env_var_if_missing "MENTOR_CHUTES_KOKORO_ENDPOINT" "https://chutes-kokoro.chutes.ai/speak"
  set_env_var_if_missing "MENTOR_CHUTES_ENABLE_KOKORO_FALLBACK" "true"
  set_env_var_if_missing "ENABLE_MENTOR_IMAGE" "true"
  set_env_var_if_missing "MENTOR_IMAGE_PROVIDER" "auto"
  set_env_var_if_missing "MENTOR_IMAGE_API_KEY" "replace_with_mentor_image_api_key_or_same_as_voice"
  set_env_var_if_missing "MENTOR_IMAGE_REQUEST_TIMEOUT_MS" "120000"
  set_env_var_if_missing "MENTOR_IMAGE_MAX_PROMPT_CHARS" "1500"
  set_env_var_if_missing "MENTOR_IMAGE_SIZE" "1024x1024"
  set_env_var_if_missing "MENTOR_IMAGE_RESPONSE_FORMAT" "url"
  set_env_var_if_missing "MENTOR_IMAGE_NUM_IMAGES" "1"
  set_env_var_if_missing "MENTOR_CHUTES_IMAGE_MODE" "run_api"
  set_env_var_if_missing "MENTOR_CHUTES_IMAGE_RUN_ENDPOINT" "https://llm.chutes.ai/v1/run"
  set_env_var_if_missing "MENTOR_CHUTES_IMAGE_MODEL" "black-forest-labs/FLUX.1-schnell"
  set_env_var_if_missing "MENTOR_CHUTES_IMAGE_ENDPOINT" ""
  set_env_var_if_missing "MENTOR_NOVITA_API_BASE_URL" "https://api.novita.ai"
  set_env_var_if_missing "MENTOR_NOVITA_API_KEY" "replace_with_novita_api_key_if_using_novita"
  set_env_var_if_missing "MENTOR_NOVITA_IMAGE_ENDPOINT" "https://api.novita.ai/v3/seedream-3-0-txt2img"
  set_env_var_if_missing "MENTOR_NOVITA_IMAGE_MODEL" "seedream-3.0"
  set_env_var_if_missing "MENTOR_NOVITA_RESPONSE_FORMAT" "url"
  set_env_var_if_missing "ENABLE_MENTOR_VIDEO" "true"
  set_env_var_if_missing "MENTOR_VIDEO_PROVIDER" "auto"
  set_env_var_if_missing "MENTOR_VIDEO_API_KEY" "replace_with_mentor_video_api_key_or_same_as_image"
  set_env_var_if_missing "MENTOR_VIDEO_REQUEST_TIMEOUT_MS" "180000"
  set_env_var_if_missing "MENTOR_VIDEO_DURATION_SECONDS" "5"
  set_env_var_if_missing "MENTOR_VIDEO_SIZE" "1024x576"
  set_env_var_if_missing "MENTOR_CHUTES_VIDEO_MODE" "run_api"
  set_env_var_if_missing "MENTOR_CHUTES_VIDEO_RUN_ENDPOINT" "https://llm.chutes.ai/v1/run"
  set_env_var_if_missing "MENTOR_CHUTES_VIDEO_MODEL" "genmo/mochi-1-preview"
  set_env_var_if_missing "MENTOR_CHUTES_VIDEO_ENDPOINT" ""
  set_env_var_if_missing "MENTOR_NOVITA_VIDEO_ENDPOINT" "https://api.novita.ai/v3/video/t2v"
  set_env_var_if_missing "MENTOR_NOVITA_VIDEO_MODEL" "seedance-1.0"
  set_env_var_if_missing "MENTOR_VOICE_SAMPLE_SOURCE_PATH" "./mentor/master-voice.wav"
  set_env_var_if_missing "MENTOR_VOICE_SAMPLE_PATH" "/data/mentor/master-voice.wav"
  set_env_var_if_missing "MENTOR_VOICE_CONTEXT_PATH" "/data/mentor/voice_context.txt"
  set_env_var_if_missing "MENTOR_VOICE_AUTO_TRANSCRIBE" "true"
  set_env_var_if_missing "ENABLE_VOICE" "true"
  set_env_var_if_missing "VOICE_MODE" "chutes_direct"
  set_env_var_if_missing "VOICE_API_KEY" "replace_with_voice_api_key_or_same_as_main"
  set_env_var_if_missing "VOICE_CHUTES_WHISPER_ENDPOINT" "https://chutes-whisper-large-v3.chutes.ai/transcribe"
  set_env_var_if_missing "VOICE_CHUTES_CSM_ENDPOINT" "https://chutes-csm-1b.chutes.ai/speak"
  set_env_var_if_missing "VOICE_CHUTES_KOKORO_ENDPOINT" "https://chutes-kokoro.chutes.ai/speak"
  set_env_var_if_missing "MCP_CAMOUFOX_DEFAULT_ENABLED" "true"
  set_env_var_if_missing "MCP_MENTOR_DEFAULT_ENABLED" "true"

  set_env_var_if_missing "TELEGRAM_BOT_TOKEN" "replace_with_telegram_bot_token"
  set_env_var_if_missing "TELEGRAM_WEBHOOK_SECRET" "$(openssl rand -hex 32)"
  set_env_var_if_missing "TELEGRAM_ALLOWED_CHAT_IDS" ""
  set_env_var_if_missing "TELEGRAM_AUTO_BIND_FIRST_CHAT" "true"
  set_env_var_if_missing "TELEGRAM_AUTO_BIND_TIMEOUT_SECONDS" "120"
  set_env_var_if_missing "TUNNEL_URL" ""
  set_env_var_if_missing "WASM_CHANNELS_DIR" "/home/ironclaw/.ironclaw/channels-v2"
  set_env_var_if_missing "WASM_CHANNEL_FORCE_SYNC" "telegram"
  set_env_var_if_missing "SECRETS_MASTER_KEY" "$(openssl rand -hex 32)"
  set_env_var_if_missing "TELEGRAM_WEBHOOK_PATH" "/webhook/telegram"

  set_env_var_if_missing "BROWSER_CHALLENGE_KEYWORDS" "captcha,verify you are human,security check,mfa,one-time code,unusual traffic,access denied"
  set_env_var_if_missing "CAMOUFOX_HEADLESS" "true"
  set_env_var_if_missing "CAMOUFOX_DEFAULT_TIMEOUT_MS" "25000"
  set_env_var_if_missing "TUNNEL_MODE" "cloudflared"

  set_env_var_if_missing "DOMAIN" "replace_with_vps_domain"
  set_env_var_if_missing "ACME_EMAIL" "ops@example.com"
  set_env_var_if_missing "VPS_HOST" "replace_with_vps_host"
  set_env_var_if_missing "VPS_USER" "root"
  set_env_var_if_missing "VPS_SSH_KEY" ""
  set_env_var_if_missing "VPS_REMOTE_DIR" "/opt/ghostclaw"

  local mentor_llm_api_key
  mentor_llm_api_key="$(read_env_var MENTOR_LLM_API_KEY)"
  if is_placeholder_or_empty "$mentor_llm_api_key"; then
    local sub_llm_api_key
    sub_llm_api_key="$(read_env_var SUB_LLM_API_KEY)"
    if ! is_placeholder_or_empty "$sub_llm_api_key"; then
      upsert_env_var "MENTOR_LLM_API_KEY" "$sub_llm_api_key"
    fi
  fi

  local mentor_llm_base
  mentor_llm_base="$(read_env_var MENTOR_LLM_BASE_URL)"
  if is_placeholder_or_empty "$mentor_llm_base"; then
    local sub_llm_base
    sub_llm_base="$(read_env_var SUB_LLM_BASE_URL)"
    if ! is_placeholder_or_empty "$sub_llm_base"; then
      upsert_env_var "MENTOR_LLM_BASE_URL" "$sub_llm_base"
    fi
  fi

  local mentor_llm_model
  mentor_llm_model="$(read_env_var MENTOR_LLM_MODEL)"
  if is_placeholder_or_empty "$mentor_llm_model"; then
    local sub_llm_model
    sub_llm_model="$(read_env_var SUB_LLM_MODEL)"
    if ! is_placeholder_or_empty "$sub_llm_model"; then
      upsert_env_var "MENTOR_LLM_MODEL" "$sub_llm_model"
    fi
  fi

  if [[ "$(read_env_var MENTOR_NAME)" == "Ghostclaw Mentor" ]]; then
    upsert_env_var "MENTOR_NAME" "Lippyclaw Mentor"
  fi

  local mentor_voice_api_key
  mentor_voice_api_key="$(read_env_var MENTOR_VOICE_API_KEY)"
  if is_placeholder_or_empty "$mentor_voice_api_key"; then
    local main_llm_api_key
    main_llm_api_key="$(read_env_var MAIN_LLM_API_KEY)"
    if ! is_placeholder_or_empty "$main_llm_api_key"; then
      upsert_env_var "MENTOR_VOICE_API_KEY" "$main_llm_api_key"
    fi
  fi

  local mentor_fish_api_key
  mentor_fish_api_key="$(read_env_var MENTOR_FISH_API_KEY)"
  if is_placeholder_or_empty "$mentor_fish_api_key"; then
    mentor_voice_api_key="$(read_env_var MENTOR_VOICE_API_KEY)"
    if ! is_placeholder_or_empty "$mentor_voice_api_key"; then
      upsert_env_var "MENTOR_FISH_API_KEY" "$mentor_voice_api_key"
    fi
  fi

  local mentor_image_api_key
  mentor_image_api_key="$(read_env_var MENTOR_IMAGE_API_KEY)"
  if is_placeholder_or_empty "$mentor_image_api_key"; then
    mentor_voice_api_key="$(read_env_var MENTOR_VOICE_API_KEY)"
    if ! is_placeholder_or_empty "$mentor_voice_api_key"; then
      upsert_env_var "MENTOR_IMAGE_API_KEY" "$mentor_voice_api_key"
    fi
  fi

  local mentor_video_api_key
  mentor_video_api_key="$(read_env_var MENTOR_VIDEO_API_KEY)"
  if is_placeholder_or_empty "$mentor_video_api_key"; then
    mentor_image_api_key="$(read_env_var MENTOR_IMAGE_API_KEY)"
    if ! is_placeholder_or_empty "$mentor_image_api_key"; then
      upsert_env_var "MENTOR_VIDEO_API_KEY" "$mentor_image_api_key"
    else
      mentor_voice_api_key="$(read_env_var MENTOR_VOICE_API_KEY)"
      if ! is_placeholder_or_empty "$mentor_voice_api_key"; then
        upsert_env_var "MENTOR_VIDEO_API_KEY" "$mentor_voice_api_key"
      fi
    fi
  fi

  local voice_api_key
  voice_api_key="$(read_env_var VOICE_API_KEY)"
  if is_placeholder_or_empty "$voice_api_key"; then
    local main_llm_api_key
    main_llm_api_key="$(read_env_var MAIN_LLM_API_KEY)"
    if ! is_placeholder_or_empty "$main_llm_api_key"; then
      upsert_env_var "VOICE_API_KEY" "$main_llm_api_key"
    fi
  fi

  generate_secret_if_missing "POSTGRES_PASSWORD" 32
  generate_secret_if_missing "INTERNAL_API_TOKEN" 48
  generate_secret_if_missing "GATEWAY_AUTH_TOKEN" 32
  generate_secret_if_missing "TELEGRAM_WEBHOOK_SECRET" 32
  generate_secret_if_missing "SECRETS_MASTER_KEY" 32
  # Fixed ports by default for deterministic local/VPS behavior.
  upsert_env_var "LOCAL_HTTP_PORT" "8080"
  upsert_env_var "LOCAL_HTTPS_PORT" "8443"
  upsert_env_var "IRONCLAW_HOST_PORT" "8082"
  upsert_env_var "TELEGRAM_WEBHOOK_PATH" "/webhook/telegram"

  local database_url
  database_url="postgresql://$(read_env_var POSTGRES_USER):$(read_env_var POSTGRES_PASSWORD)@postgres:5432/$(read_env_var POSTGRES_DB)"
  upsert_env_var "DATABASE_URL" "$database_url"

  prompt_required_if_missing "IRONCLAW_GIT_URL" "Official IronClaw Git URL: " false
  prompt_required_if_missing "IRONCLAW_GIT_REF" "Official IronClaw Git ref (tag/commit): " false

  local lippyclaw_git_url
  lippyclaw_git_url="$(read_env_var LIPPYCLAW_GIT_URL)"
  if is_placeholder_or_empty "$lippyclaw_git_url"; then
    upsert_env_var "LIPPYCLAW_GIT_URL" "$(read_env_var IRONCLAW_GIT_URL)"
  fi

  local lippyclaw_git_ref
  lippyclaw_git_ref="$(read_env_var LIPPYCLAW_GIT_REF)"
  if is_placeholder_or_empty "$lippyclaw_git_ref"; then
    upsert_env_var "LIPPYCLAW_GIT_REF" "$(read_env_var IRONCLAW_GIT_REF)"
  fi

  echo "[init] optional LLM/Telegram settings can be configured later via onboard or .env"

  chmod 600 "$ENV_FILE"

  echo "[init] wrote $ENV_FILE"
  echo "[init] local HTTP port: $(read_env_var LOCAL_HTTP_PORT)"
  echo "[init] local HTTPS port: $(read_env_var LOCAL_HTTPS_PORT)"
  echo "[init] ironclaw direct port: $(read_env_var IRONCLAW_HOST_PORT)"
}

validate_env() {
  local required=(
    IRONCLAW_GIT_URL
    IRONCLAW_GIT_REF
    POSTGRES_DB
    POSTGRES_USER
    POSTGRES_PASSWORD
    SECRETS_MASTER_KEY
    GATEWAY_AUTH_TOKEN
  )

  local key
  for key in "${required[@]}"; do
    local value
    value="$(read_env_var "$key")"
    if is_placeholder_or_empty "$value"; then
      echo "ERROR: required env var missing or placeholder: $key" >&2
      exit 1
    fi
  done
}

validate_ironclaw_build_env() {
  local key
  for key in IRONCLAW_GIT_URL IRONCLAW_GIT_REF; do
    local value
    value="$(read_env_var "$key")"
    if is_placeholder_or_empty "$value"; then
      echo "ERROR: required env var missing or placeholder for ironclaw build: $key" >&2
      exit 1
    fi
  done
}

validate_lippyclaw_build_env() {
  local key
  for key in LIPPYCLAW_GIT_URL LIPPYCLAW_GIT_REF; do
    local value
    value="$(read_env_var "$key")"
    if is_placeholder_or_empty "$value"; then
      echo "ERROR: required env var missing or placeholder for sidecar build: $key" >&2
      exit 1
    fi
  done
}

is_buildable_service() {
  local candidate="$1"
  local svc
  for svc in "${BUILDABLE_SERVICES[@]}"; do
    if [[ "$svc" == "$candidate" ]]; then
      return 0
    fi
  done
  return 1
}

build_images() {
  local target="${1:-all}"
  shift || true

  local no_cache="false"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-cache)
        no_cache="true"
        ;;
      *)
        echo "ERROR: unknown build option: $1" >&2
        echo "Usage: ./scripts/ghostclaw.sh build [all|service] [--no-cache]" >&2
        exit 1
        ;;
    esac
    shift
  done

  local -a targets
  if [[ -z "$target" || "$target" == "all" ]]; then
    targets=("${BUILDABLE_SERVICES[@]}")
  else
    if ! is_buildable_service "$target"; then
      echo "ERROR: unknown build target: $target" >&2
      echo "Buildable services: ${BUILDABLE_SERVICES[*]}" >&2
      exit 1
    fi
    targets=("$target")
  fi

  local need_ironclaw_build_env=0
  local need_lippyclaw_build_env=0
  local svc
  for svc in "${targets[@]}"; do
    if [[ "$svc" == "ironclaw" ]]; then
      need_ironclaw_build_env=1
    fi
    if [[ "$svc" == "mentor-mcp" || "$svc" == "voice-mcp" ]]; then
      need_lippyclaw_build_env=1
    fi
  done

  if [[ "$need_ironclaw_build_env" -eq 1 ]]; then
    validate_ironclaw_build_env
  fi
  if [[ "$need_lippyclaw_build_env" -eq 1 ]]; then
    validate_lippyclaw_build_env
  fi

  local -a build_cmd
  build_cmd=(build)
  if [[ "$no_cache" == "true" ]]; then
    build_cmd+=(--no-cache)
  fi
  build_cmd+=("${targets[@]}")

  echo "[build] building: ${targets[*]}"
  if [[ "$no_cache" == "true" ]]; then
    echo "[build] cache: disabled"
  fi
  compose_local "${build_cmd[@]}"
  echo "[build] done"
}

telegram_configured() {
  local telegram_token
  telegram_token="$(read_env_var TELEGRAM_BOT_TOKEN)"
  if is_placeholder_or_empty "$telegram_token"; then
    return 1
  fi
  return 0
}

validate_telegram_env() {
  if ! telegram_configured; then
    echo "ERROR: TELEGRAM_BOT_TOKEN is not configured. Set it in .env or via onboard." >&2
    exit 1
  fi

  local telegram_token
  telegram_token="$(read_env_var TELEGRAM_BOT_TOKEN)"
  if ! echo "$telegram_token" | grep -Eq '^[0-9]+:[A-Za-z0-9_-]+$'; then
    echo "ERROR: TELEGRAM_BOT_TOKEN format looks invalid. Expected <digits>:<token>." >&2
    exit 1
  fi

  local webhook_secret
  webhook_secret="$(read_env_var TELEGRAM_WEBHOOK_SECRET)"
  if is_placeholder_or_empty "$webhook_secret"; then
    echo "ERROR: TELEGRAM_WEBHOOK_SECRET is missing." >&2
    exit 1
  fi
}
wait_for_postgres() {
  local db_user
  local db_name
  db_user="$(read_env_var POSTGRES_USER)"
  db_name="$(read_env_var POSTGRES_DB)"

  local attempt=1
  until compose_local exec -T postgres pg_isready -U "$db_user" -d "$db_name" >/dev/null 2>&1; do
    if [[ "$attempt" -ge 40 ]]; then
      echo "ERROR: postgres is not ready" >&2
      exit 1
    fi
    attempt=$((attempt + 1))
    sleep 2
  done
}

ensure_pgvector() {
  local db_user
  local db_name
  db_user="$(read_env_var POSTGRES_USER)"
  db_name="$(read_env_var POSTGRES_DB)"

  compose_local exec -T postgres psql -U "$db_user" -d "$db_name" \
    -c "CREATE EXTENSION IF NOT EXISTS vector;" >/dev/null
}

ensure_ironclaw_home_writable() {
  log "INFO" "preflight: fixing /home/ironclaw/.ironclaw ownership"
  run_with_timeout 300 compose_local run --rm --no-deps --user root --entrypoint bash ironclaw -lc \
    'mkdir -p /home/ironclaw/.ironclaw && chown -R 1001:1001 /home/ironclaw/.ironclaw'
  log "INFO" "preflight: ownership check completed"
}

api_base_url() {
  local host_port
  host_port="$(read_env_var IRONCLAW_HOST_PORT)"
  if [[ -z "$host_port" ]]; then
    host_port="8082"
  fi
  echo "http://localhost:${host_port}"
}

wait_for_ironclaw() {
  local base
  base="$(api_base_url)"

  local attempt=1
  until curl -fsS "$base/healthz" >/dev/null 2>&1 || curl -fsS "$base/" >/dev/null 2>&1; do
    if [[ "$attempt" -ge 45 ]]; then
      echo "ERROR: ironclaw endpoint is not healthy at $base" >&2
      exit 1
    fi
    attempt=$((attempt + 1))
    sleep 2
  done
}

check_camoufox_tool() {
  if ! compose_local exec -T camoufox-tool node -e "fetch('http://127.0.0.1:8788/healthz').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))" >/dev/null 2>&1; then
    echo "ERROR: camoufox-tool health check failed" >&2
    exit 1
  fi
}

check_camoufox_mcp() {
  if ! compose_local exec -T camoufox-mcp node -e "fetch('http://127.0.0.1:8790/healthz').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))" >/dev/null 2>&1; then
    echo "ERROR: camoufox-mcp health check failed" >&2
    exit 1
  fi
}

camoufox_mcp_registered() {
  local list_output
  list_output="$(compose_local run --rm --no-deps ironclaw mcp list 2>/dev/null || true)"
  if echo "$list_output" | grep -Eq "(^|[[:space:]])camoufox([[:space:]]|$)"; then
    return 0
  fi
  return 1
}

mcp_default_enabled() {
  local key="$1"
  local value
  value="$(read_env_var "$key")"
  if [[ "$value" == "false" ]]; then
    return 1
  fi
  return 0
}

ensure_camoufox_mcp_registered() {
  if camoufox_mcp_registered; then
    echo "[mcp] camoufox MCP already registered"
    return 1
  fi

  if ! compose_local run --rm --no-deps ironclaw mcp add camoufox http://camoufox-mcp:8790/mcp --description "Camoufox browser automation bridge"; then
    echo "[mcp] warning: failed to register camoufox MCP server (continuing startup)" >&2
    echo "[mcp] hint: rebuild ironclaw image so Docker MCP endpoint validation patch is active." >&2
    return 2
  fi

  if ! mcp_default_enabled "MCP_CAMOUFOX_DEFAULT_ENABLED"; then
    if compose_local run --rm --no-deps ironclaw mcp toggle camoufox --disable >/dev/null 2>&1; then
      echo "[mcp] camoufox MCP defaulted to disabled (MCP_CAMOUFOX_DEFAULT_ENABLED=false)"
    else
      echo "[mcp] warning: camoufox MCP added but could not be default-disabled" >&2
    fi
  fi

  echo "[mcp] registered camoufox MCP server"
  return 0
}

check_mentor_mcp() {
  if ! compose_local exec -T mentor-mcp node -e "fetch('http://127.0.0.1:8791/healthz').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))" >/dev/null 2>&1; then
    echo "ERROR: mentor-mcp health check failed" >&2
    exit 1
  fi
}

mentor_mcp_registered() {
  local list_output
  list_output="$(compose_local run --rm --no-deps ironclaw mcp list 2>/dev/null || true)"
  if echo "$list_output" | grep -Eq "(^|[[:space:]])mentor([[:space:]]|$)"; then
    return 0
  fi
  return 1
}

ensure_mentor_mcp_registered() {
  if mentor_mcp_registered; then
    echo "[mcp] mentor MCP already registered"
    return 1
  fi

  if ! compose_local run --rm --no-deps ironclaw mcp add mentor http://mentor-mcp:8791/mcp --description "Mentor persona with memory + voice tools"; then
    echo "[mcp] warning: failed to register mentor MCP server (continuing startup)" >&2
    echo "[mcp] hint: run ./scripts/ghostclaw.sh build ironclaw then ./scripts/ghostclaw.sh restart" >&2
    return 2
  fi

  if ! mcp_default_enabled "MCP_MENTOR_DEFAULT_ENABLED"; then
    if compose_local run --rm --no-deps ironclaw mcp toggle mentor --disable >/dev/null 2>&1; then
      echo "[mcp] mentor MCP defaulted to disabled (MCP_MENTOR_DEFAULT_ENABLED=false)"
    else
      echo "[mcp] warning: mentor MCP added but could not be default-disabled" >&2
    fi
  fi

  echo "[mcp] registered mentor MCP server"
  return 0
}

set_telegram_bot_commands() {
  if ! telegram_configured; then
    echo "[telegram] token not configured, skipping setMyCommands"
    return 0
  fi

  local bot_token
  bot_token="$(read_env_var TELEGRAM_BOT_TOKEN)"
  local payload
  payload='{"commands":[{"command":"help","description":"Show command list"},{"command":"mentor","description":"Chat with mentor"},{"command":"mentor_voice","description":"Mentor reply with voice"},{"command":"mentor_image","description":"Generate mentor image"},{"command":"mentor_video","description":"Generate mentor video"},{"command":"run","description":"Queue browser run"},{"command":"job","description":"Check job status"}]}'

  local response_file
  response_file="$(mktemp)"

  local http_code
  http_code=$(curl -sS --connect-timeout 10 --max-time 20 -o "$response_file" -w "%{http_code}" -X POST "https://api.telegram.org/bot${bot_token}/setMyCommands"     -H "Content-Type: application/json"     -d "$payload" || true)

  local response
  response="$(cat "$response_file" 2>/dev/null || true)"
  rm -f "$response_file"

  if [[ "$http_code" != "200" ]]; then
    echo "[telegram] warning: setMyCommands HTTP $http_code" >&2
    echo "$response" >&2
    return 1
  fi

  if echo "$response" | grep -q '"ok":true'; then
    echo "[telegram] bot commands configured (open chat and type / to refresh command menu)"
    return 0
  fi

  echo "[telegram] warning: setMyCommands returned non-ok response" >&2
  echo "$response" >&2
  return 1
}

extract_chat_id_from_ironclaw_logs() {
  local since_ts="$1"
  local raw
  raw="$(compose_local logs --no-color --since "$since_ts" ironclaw 2>/dev/null || true)"
  if [[ -z "$raw" ]]; then
    return 1
  fi

  local cleaned
  cleaned="$(printf '%s\n' "$raw" | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g')"

  local line
  line="$(printf '%s\n' "$cleaned" | grep -E 'WASM emit_message called .*user_id=' | tail -n 1 || true)"
  if [[ -z "$line" ]]; then
    return 1
  fi

  local chat_id
  chat_id="$(printf '%s\n' "$line" | sed -E 's/.*user_id=([-0-9]+).*/\1/' || true)"
  if [[ -z "$chat_id" || ! "$chat_id" =~ ^-?[0-9]+$ ]]; then
    return 1
  fi

  printf '%s\n' "$chat_id"
  return 0
}

auto_bind_telegram_allowed_chat_id() {
  if ! telegram_configured; then
    return 0
  fi

  local current_allowed
  current_allowed="$(read_env_var TELEGRAM_ALLOWED_CHAT_IDS)"
  if [[ -n "$current_allowed" ]]; then
    echo "[telegram] allowlist already configured: $current_allowed"
    return 0
  fi

  local auto_bind
  auto_bind="$(read_env_var TELEGRAM_AUTO_BIND_FIRST_CHAT)"
  if [[ "$auto_bind" != "true" ]]; then
    echo "[telegram] auto-bind disabled (TELEGRAM_AUTO_BIND_FIRST_CHAT=$auto_bind)"
    return 0
  fi

  local timeout_seconds
  timeout_seconds="$(read_env_var TELEGRAM_AUTO_BIND_TIMEOUT_SECONDS)"
  if [[ -z "$timeout_seconds" || ! "$timeout_seconds" =~ ^[0-9]+$ ]]; then
    timeout_seconds="120"
  fi

  local since_ts
  since_ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  local started_at
  started_at="$(date +%s)"

  echo "[telegram] TELEGRAM_ALLOWED_CHAT_IDS is empty."
  echo "[telegram] Auto-bind is enabled: send any message to your bot now."
  echo "[telegram] Waiting up to ${timeout_seconds}s for first message..."

  local chat_id=""
  while true; do
    chat_id="$(extract_chat_id_from_ironclaw_logs "$since_ts" || true)"
    if [[ -n "$chat_id" ]]; then
      break
    fi

    local now
    now="$(date +%s)"
    local elapsed=$((now - started_at))
    if (( elapsed >= timeout_seconds )); then
      echo "[telegram] No inbound message observed within ${timeout_seconds}s."
      echo "[telegram] Leaving TELEGRAM_ALLOWED_CHAT_IDS empty (open access)."
      echo "[telegram] Run ./scripts/ghostclaw.sh telegram:autobind after messaging the bot."
      return 0
    fi
    sleep 2
  done

  upsert_env_var "TELEGRAM_ALLOWED_CHAT_IDS" "$chat_id"
  echo "[telegram] Auto-bound TELEGRAM_ALLOWED_CHAT_IDS=$chat_id"
  echo "[telegram] Restarting ironclaw to apply allowlist..."
  compose_local restart ironclaw
  wait_for_ironclaw
}

resolve_mentor_voice_source() {
  local preferred="${1:-}"
  if [[ -n "$preferred" ]]; then
    if [[ "$preferred" == /* ]]; then
      if [[ -f "$preferred" ]]; then
        echo "$preferred"
        return 0
      fi
    else
      local preferred_rel="$REPO_ROOT/${preferred#./}"
      if [[ -f "$preferred_rel" ]]; then
        echo "$preferred_rel"
        return 0
      fi
    fi
  fi

  local configured
  configured="$(read_env_var MENTOR_VOICE_SAMPLE_SOURCE_PATH)"
  if [[ -n "$configured" ]]; then
    if [[ "$configured" == /* ]]; then
      if [[ -f "$configured" ]]; then
        echo "$configured"
        return 0
      fi
    else
      local configured_rel="$REPO_ROOT/${configured#./}"
      if [[ -f "$configured_rel" ]]; then
        echo "$configured_rel"
        return 0
      fi
    fi
  fi

  local -a candidates=(
    "$REPO_ROOT/mentor/master-voice.wav"
    "$REPO_ROOT/data/mentor/master-voice.wav"
    "$REPO_ROOT/mentor/master-voice.mp3"
    "$REPO_ROOT/data/mentor/master-voice.mp3"
    "$REPO_ROOT/mentor/master-voice.m4a"
    "$REPO_ROOT/data/mentor/master-voice.m4a"
    "$REPO_ROOT/mentor/master-voice.mp4"
    "$REPO_ROOT/data/mentor/master-voice.mp4"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

sync_mentor_voice_sample() {
  local sample_source_input="${1:-}"
  local sample_source
  sample_source="$(resolve_mentor_voice_source "$sample_source_input" || true)"

  if [[ -z "$sample_source" ]]; then
    echo "ERROR: mentor voice sample file not found. Expected one of:" >&2
    echo "  ./mentor/master-voice.wav" >&2
    echo "  ./data/mentor/master-voice.wav" >&2
    echo "Or pass a path: ./scripts/ghostclaw.sh up /abs/path/master-voice.wav" >&2
    exit 1
  fi

  local ext
  ext="${sample_source##*.}"
  ext="${ext,,}"
  case "$ext" in
    mp3|mp4|m4a|wav|ogg|webm) ;;
    *) ext="mp3" ;;
  esac

  local target_rel="./data/mentor/master-voice.${ext}"
  local target_sample="$REPO_ROOT/${target_rel#./}"
  if [[ "$sample_source" != "$target_sample" ]]; then
    cp "$sample_source" "$target_sample"
  fi

  upsert_env_var "MENTOR_VOICE_SAMPLE_SOURCE_PATH" "$target_rel"
  upsert_env_var "MENTOR_VOICE_SAMPLE_PATH" "/data/mentor/master-voice.${ext}"
  echo "[mentor] sample synced: $target_sample"
}

bootstrap_mentor_voice_context() {
  local sample_source_input="${1:-}"

  sync_mentor_voice_sample "$sample_source_input"

  local mentor_voice_api_key
  mentor_voice_api_key="$(read_env_var MENTOR_VOICE_API_KEY)"
  if is_placeholder_or_empty "$mentor_voice_api_key"; then
    echo "ERROR: MENTOR_VOICE_API_KEY is missing or placeholder." >&2
    exit 1
  fi

  compose_local up -d mentor-mcp
  check_mentor_mcp

  echo "[mentor] bootstrapping voice context via whisper..."
  compose_local exec -T mentor-mcp node -e "fetch('http://127.0.0.1:8791/bootstrap/voice',{method:'POST'}).then(async r=>{const t=await r.text();console.log(t);process.exit(r.ok?0:1)}).catch(e=>{console.error(e);process.exit(1)})"

  local context_env
  context_env="$(read_env_var MENTOR_VOICE_CONTEXT_PATH)"
  local context_file="$REPO_ROOT/data/mentor/voice_context.txt"
  if [[ "$context_env" == /data/mentor/* ]]; then
    context_file="$REPO_ROOT/data/mentor/${context_env##*/}"
  elif [[ -n "$context_env" && "$context_env" == /* ]]; then
    context_file="$context_env"
  elif [[ -n "$context_env" ]]; then
    context_file="$REPO_ROOT/${context_env#./}"
  fi

  if [[ ! -s "$context_file" ]]; then
    echo "ERROR: mentor voice context file was not generated: $context_file" >&2
    exit 1
  fi

  echo "[mentor] voice context ready: $context_file"
}

auto_bootstrap_mentor_voice_if_enabled() {
  local enabled
  enabled="$(read_env_var MENTOR_AUTO_BOOTSTRAP_VOICE)"
  if [[ "$enabled" != "true" ]]; then
    return 0
  fi

  local voice_enabled
  voice_enabled="$(read_env_var ENABLE_MENTOR_VOICE)"
  if [[ "$voice_enabled" != "true" ]]; then
    return 0
  fi

  local context_env
  context_env="$(read_env_var MENTOR_VOICE_CONTEXT_PATH)"
  local context_file="$REPO_ROOT/data/mentor/voice_context.txt"
  if [[ "$context_env" == /data/mentor/* ]]; then
    context_file="$REPO_ROOT/data/mentor/${context_env##*/}"
  elif [[ -n "$context_env" && "$context_env" == /* ]]; then
    context_file="$context_env"
  elif [[ -n "$context_env" ]]; then
    context_file="$REPO_ROOT/${context_env#./}"
  fi

  if [[ -s "$context_file" ]]; then
    echo "[mentor] voice context already present, skipping bootstrap"
    return 0
  fi

  local mentor_voice_api_key
  mentor_voice_api_key="$(read_env_var MENTOR_VOICE_API_KEY)"
  if is_placeholder_or_empty "$mentor_voice_api_key"; then
    echo "[mentor] MENTOR_VOICE_API_KEY missing; skipping automatic voice bootstrap"
    return 0
  fi

  local sample_source
  sample_source="$(read_env_var MENTOR_VOICE_SAMPLE_SOURCE_PATH)"
  if [[ -z "$sample_source" ]]; then
    echo "[mentor] MENTOR_VOICE_SAMPLE_SOURCE_PATH missing; skipping automatic voice bootstrap"
    return 0
  fi

  local resolved_source="$sample_source"
  if [[ "$resolved_source" != /* ]]; then
    resolved_source="$REPO_ROOT/${resolved_source#./}"
  fi
  if [[ ! -f "$resolved_source" ]]; then
    echo "[mentor] voice sample not found at $resolved_source; skipping automatic bootstrap"
    return 0
  fi

  if ! bootstrap_mentor_voice_context "$resolved_source"; then
    echo "[mentor] warning: automatic voice bootstrap failed; continuing startup"
    echo "[mentor] hint: verify MENTOR_CHUTES_*_ENDPOINT or MENTOR_CHUTES_RUN_ENDPOINT and rerun ./scripts/ghostclaw.sh mentor:clone"
    return 0
  fi
}
discover_local_tunnel_url() {
  if [[ -n "${LOCAL_TUNNEL_URL:-}" ]]; then
    echo "$LOCAL_TUNNEL_URL"
    return
  fi

  local attempts=1
  while [[ "$attempts" -le 30 ]]; do
    local url
    url="$({ compose_local logs --no-color cloudflared 2>/dev/null || true; } | grep -Eo 'https://[-a-zA-Z0-9]+\.trycloudflare\.com' | tail -n 1)"
    if [[ -n "$url" ]]; then
      echo "$url"
      return
    fi
    attempts=$((attempts + 1))
    sleep 2
  done

  echo "ERROR: failed to discover cloudflared public URL from logs." >&2
  echo "Hint: docker compose --env-file $ENV_FILE -f $REPO_ROOT/docker-compose.yml -f $REPO_ROOT/docker-compose.local.yml logs cloudflared" >&2
  exit 1
}

wait_for_tunnel_ready() {
  local tunnel_url="$1"
  local attempts=1

  while [[ "$attempts" -le 30 ]]; do
    if curl -sS --connect-timeout 5 --max-time 8 -o /dev/null "$tunnel_url/"; then
      return 0
    fi
    attempts=$((attempts + 1))
    sleep 2
  done

  echo "ERROR: tunnel URL is not reachable yet: $tunnel_url" >&2
  echo "Hint: check cloudflared logs and DNS propagation before starting ironclaw" >&2
  exit 1
}

configure_local_tunnel_url() {
  if ! telegram_configured; then
    return 0
  fi

  local tunnel_url
  tunnel_url="$(discover_local_tunnel_url)"
  wait_for_tunnel_ready "$tunnel_url"
  upsert_env_var "TUNNEL_URL" "$tunnel_url"
  echo "[tunnel] configured TUNNEL_URL=$tunnel_url"
}

set_telegram_webhook() {
  local mode="$1"

  validate_telegram_env
  local bot_token
  local secret_token
  local webhook_path
  bot_token="$(read_env_var TELEGRAM_BOT_TOKEN)"
  secret_token="$(read_env_var TELEGRAM_WEBHOOK_SECRET)"
  webhook_path="$(read_env_var TELEGRAM_WEBHOOK_PATH)"

  if [[ -z "$webhook_path" ]]; then
    webhook_path="/webhook/telegram"
  fi

  local base_url
  case "$mode" in
    local)
      base_url="$(discover_local_tunnel_url)"
      ;;
    vps)
      local domain
      domain="$(read_env_var DOMAIN)"
      if is_placeholder_or_empty "$domain"; then
        echo "ERROR: DOMAIN is required for VPS webhook setup" >&2
        exit 1
      fi
      base_url="https://${domain}"
      ;;
    *)
      echo "ERROR: invalid webhook mode: $mode" >&2
      exit 1
      ;;
  esac

  local webhook_url
  webhook_url="${base_url}${webhook_path}"
  local payload
  payload=$(printf '{"url":"%s","secret_token":"%s","drop_pending_updates":true}' "$webhook_url" "$secret_token")

  local response_file
  local http_code
  response_file="$(mktemp)"

  http_code=$(curl -sS --connect-timeout 10 --max-time 20 -o "$response_file" -w "%{http_code}" -X POST "https://api.telegram.org/bot${bot_token}/setWebhook" \
    -H "Content-Type: application/json" \
    -d "$payload" || true)

  local response
  response="$(cat "$response_file" 2>/dev/null || true)"
  rm -f "$response_file"

  if [[ "$http_code" != "200" ]]; then
    echo "ERROR: Telegram setWebhook HTTP $http_code" >&2
    echo "$response" >&2
    exit 1
  fi

  if echo "$response" | grep -q '"ok":true'; then
    echo "[webhook] configured: $webhook_url"
    return
  fi

  echo "ERROR: Telegram setWebhook returned non-ok response" >&2
  echo "$response" >&2
  exit 1
}

smoke_local() {
  wait_for_postgres
  ensure_pgvector
  wait_for_ironclaw
  check_camoufox_tool
  check_camoufox_mcp
  check_mentor_mcp

  if ! compose_local ps cloudflared | grep -q "Up"; then
    echo "ERROR: cloudflared is not running" >&2
    exit 1
  fi

  echo "[smoke] local stack healthy"
}

deploy_vps_release() {
  require_cmd ssh
  require_cmd scp
  require_cmd tar
  require_cmd gzip

  local vps_host
  local vps_user
  local vps_ssh_key
  local vps_remote_dir

  vps_host="$(read_env_var VPS_HOST)"
  vps_user="$(read_env_var VPS_USER)"
  vps_ssh_key="$(read_env_var VPS_SSH_KEY)"
  vps_remote_dir="$(read_env_var VPS_REMOTE_DIR)"

  local domain
  domain="$(read_env_var DOMAIN)"

  if is_placeholder_or_empty "$vps_host"; then
    echo "ERROR: VPS_HOST is required for deploy:vps" >&2
    exit 1
  fi

  if is_placeholder_or_empty "$domain"; then
    echo "ERROR: DOMAIN is required for deploy:vps" >&2
    exit 1
  fi

  if [[ -z "$vps_user" ]]; then
    vps_user="root"
  fi

  if [[ -z "$vps_remote_dir" ]]; then
    vps_remote_dir="/opt/ghostclaw"
  fi

  if [[ -n "$vps_ssh_key" && ! -f "$vps_ssh_key" ]]; then
    echo "ERROR: VPS_SSH_KEY file not found: $vps_ssh_key" >&2
    exit 1
  fi

  local release_id
  release_id="$(date -u +"%Y%m%d%H%M%S")"

  local archive_path
  local remote_archive
  local remote_env
  local target
  archive_path="/tmp/ghostclaw-${release_id}.tar.gz"
  remote_archive="/tmp/ghostclaw-${release_id}.tar.gz"
  remote_env="/tmp/ghostclaw-${release_id}.env"
  target="${vps_user}@${vps_host}"

  local -a ssh_opts
  ssh_opts=(-o StrictHostKeyChecking=accept-new)
  if [[ -n "$vps_ssh_key" ]]; then
    ssh_opts+=(-i "$vps_ssh_key")
  fi

  echo "[deploy:vps] building release archive..."
  (
    cd "$REPO_ROOT"
    tar -czf "$archive_path" \
      camoufox-tool \
      camoufox-mcp \
      mentor-mcp \
      mentor \
      docker \
      infra \
      scripts \
      docker-compose.yml \
      docker-compose.local.yml \
      docker-compose.vps.yml \
      README.md \
      .roorules.md \
      .dockerignore
  )

  echo "[deploy:vps] uploading to $target..."
  scp "${ssh_opts[@]}" "$archive_path" "$target:$remote_archive"
  scp "${ssh_opts[@]}" "$ENV_FILE" "$target:$remote_env"

  echo "[deploy:vps] deploying remote release..."
  ssh "${ssh_opts[@]}" "$target" \
    "RELEASE_ID='$release_id' REMOTE_DIR='$vps_remote_dir' REMOTE_ARCHIVE='$remote_archive' REMOTE_ENV='$remote_env' bash -s" <<'REMOTE_SCRIPT'
set -Eeuo pipefail

if command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
else
  SUDO=""
fi

if ! command -v docker >/dev/null 2>&1; then
  $SUDO apt-get update -y
  $SUDO apt-get install -y docker.io docker-compose-plugin curl
  $SUDO systemctl enable --now docker
fi

if ! docker compose version >/dev/null 2>&1; then
  $SUDO apt-get update -y
  $SUDO apt-get install -y docker-compose-plugin
fi

$SUDO mkdir -p "$REMOTE_DIR/releases/$RELEASE_ID"
$SUDO tar -xzf "$REMOTE_ARCHIVE" -C "$REMOTE_DIR/releases/$RELEASE_ID"
$SUDO cp "$REMOTE_ENV" "$REMOTE_DIR/releases/$RELEASE_ID/.env"
$SUDO chmod 600 "$REMOTE_DIR/releases/$RELEASE_ID/.env"

if [[ -f "$REMOTE_DIR/current_release" ]]; then
  $SUDO cp "$REMOTE_DIR/current_release" "$REMOTE_DIR/previous_release"
fi

cd "$REMOTE_DIR/releases/$RELEASE_ID"
$SUDO docker compose --env-file .env -f docker-compose.yml -f docker-compose.vps.yml up -d --build

# Ensure MCP tools are registered in official IronClaw tool registry
$SUDO docker compose --env-file .env -f docker-compose.yml -f docker-compose.vps.yml run --rm --no-deps ironclaw \
  mcp add camoufox http://camoufox-mcp:8790/mcp --description "Camoufox browser automation bridge" >/dev/null || true
$SUDO docker compose --env-file .env -f docker-compose.yml -f docker-compose.vps.yml run --rm --no-deps ironclaw \
  mcp add mentor http://mentor-mcp:8791/mcp --description "Mentor persona with memory + voice tools" >/dev/null || true
$SUDO docker compose --env-file .env -f docker-compose.yml -f docker-compose.vps.yml restart ironclaw >/dev/null || true

POSTGRES_USER="$(awk -F= '$1=="POSTGRES_USER" {print $2}' .env | tail -n1)"
POSTGRES_DB="$(awk -F= '$1=="POSTGRES_DB" {print $2}' .env | tail -n1)"
if [[ -n "$POSTGRES_USER" && -n "$POSTGRES_DB" ]]; then
  $SUDO docker compose --env-file .env -f docker-compose.yml -f docker-compose.vps.yml exec -T postgres \
    psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "CREATE EXTENSION IF NOT EXISTS vector;" >/dev/null
fi

echo "$RELEASE_ID" | $SUDO tee "$REMOTE_DIR/current_release" >/dev/null
$SUDO ln -sfn "$REMOTE_DIR/releases/$RELEASE_ID" "$REMOTE_DIR/current"

$SUDO rm -f "$REMOTE_ARCHIVE" "$REMOTE_ENV"
REMOTE_SCRIPT

  rm -f "$archive_path"

  if telegram_configured; then
    if ! (set_telegram_webhook "vps"); then
      echo "[deploy:vps] warning: telegram webhook setup failed; release is still deployed"
    fi
  else
    echo "[deploy:vps] telegram not configured, skipping webhook setup"
  fi

  echo "[deploy:vps] deployed release: $release_id"
  echo "[deploy:vps] rollback command: ./scripts/ghostclaw.sh rollback:vps"
}

rollback_vps_release() {
  require_cmd ssh

  local vps_host
  local vps_user
  local vps_ssh_key
  local vps_remote_dir

  vps_host="$(read_env_var VPS_HOST)"
  vps_user="$(read_env_var VPS_USER)"
  vps_ssh_key="$(read_env_var VPS_SSH_KEY)"
  vps_remote_dir="$(read_env_var VPS_REMOTE_DIR)"

  if is_placeholder_or_empty "$vps_host"; then
    echo "ERROR: VPS_HOST is required for rollback:vps" >&2
    exit 1
  fi

  if [[ -z "$vps_user" ]]; then
    vps_user="root"
  fi

  if [[ -z "$vps_remote_dir" ]]; then
    vps_remote_dir="/opt/ghostclaw"
  fi

  if [[ -n "$vps_ssh_key" && ! -f "$vps_ssh_key" ]]; then
    echo "ERROR: VPS_SSH_KEY file not found: $vps_ssh_key" >&2
    exit 1
  fi

  local -a ssh_opts
  ssh_opts=(-o StrictHostKeyChecking=accept-new)
  if [[ -n "$vps_ssh_key" ]]; then
    ssh_opts+=(-i "$vps_ssh_key")
  fi

  local target
  target="${vps_user}@${vps_host}"

  ssh "${ssh_opts[@]}" "$target" \
    "REMOTE_DIR='$vps_remote_dir' bash -s" <<'REMOTE_SCRIPT'
set -Eeuo pipefail

if command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
else
  SUDO=""
fi

if [[ ! -f "$REMOTE_DIR/previous_release" ]]; then
  echo "ERROR: previous release marker not found." >&2
  exit 1
fi

PREVIOUS_RELEASE="$(cat "$REMOTE_DIR/previous_release")"
if [[ -z "$PREVIOUS_RELEASE" ]]; then
  echo "ERROR: previous release marker is empty." >&2
  exit 1
fi

cd "$REMOTE_DIR/releases/$PREVIOUS_RELEASE"
$SUDO docker compose --env-file .env -f docker-compose.yml -f docker-compose.vps.yml up -d --build

echo "$PREVIOUS_RELEASE" | $SUDO tee "$REMOTE_DIR/current_release" >/dev/null
$SUDO ln -sfn "$REMOTE_DIR/releases/$PREVIOUS_RELEASE" "$REMOTE_DIR/current"

echo "Rolled back to release: $PREVIOUS_RELEASE"
REMOTE_SCRIPT
}

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/ghostclaw.sh <command>

Commands:
  init               Generate or repair .env using secure defaults
  build [target]     Build images (all or one: ironclaw|camoufox-tool|camoufox-mcp|mentor-mcp|voice-mcp|agent-sandbox)
  onboard            Run official `ironclaw onboard` inside container
  up [voice_sample]  Start local stack (auto tunnel URL + mentor voice bootstrap)
  restart [sample]   Full local restart (down + tunnel bootstrap + up + smoke)
  down               Stop local stack
  health             Show local service and endpoint health
  logs [service]     Tail logs for all services or a single service
  shell              Open interactive shell in agent-sandbox
  webhook:set        Set Telegram webhook for local tunnel (single bot token)
  telegram:commands  Register Telegram slash commands (/mentor, /mentor_voice, /mentor_image, /mentor_video, /run, /job)
  telegram:autobind  Auto-bind TELEGRAM_ALLOWED_CHAT_IDS from first inbound Telegram message
  mentor:clone [audio] Sync sample audio and bootstrap Chutes whisper context for CSM voice clone
  smoke              Validate local stack readiness
  deploy:vps         Deploy stack to Hostinger VPS
  rollback:vps       Roll back VPS to previous release

Build examples:
  ./scripts/ghostclaw.sh build
  ./scripts/ghostclaw.sh build all --no-cache
  ./scripts/ghostclaw.sh build mentor-mcp
  ./scripts/ghostclaw.sh build ironclaw

Run examples:
  ./scripts/ghostclaw.sh up
  ./scripts/ghostclaw.sh up /absolute/path/master-voice.wav
  ./scripts/ghostclaw.sh restart /absolute/path/master-voice.wav
USAGE
}

main() {
  local cmd="${1:-}"
  log "INFO" "command=${cmd:-help} log_file=$LOG_FILE"

  case "$cmd" in
    init)
      require_cmd docker
      log "INFO" "step=ensure_env_file"
      ensure_env_file
      ;;

    onboard)
      require_cmd docker
      log "INFO" "step=ensure_env_file"
      ensure_env_file
      log "INFO" "step=validate_env"
      validate_env
      log "INFO" "step=ensure_ironclaw_home_writable"
      ensure_ironclaw_home_writable
      log "INFO" "step=compose_up_for_onboard"
      compose_local up -d camoufox-tool camoufox-mcp mentor-mcp
      log "INFO" "step=run_onboard_wizard"
      compose_local run --rm ironclaw onboard
      ;;

    build)
      require_cmd docker
      log "INFO" "step=ensure_env_file"
      ensure_env_file
      build_images "${2:-all}" "${@:3}"
      ;;

    up)
      require_cmd docker
      log "INFO" "step=ensure_env_file"
      ensure_env_file
      log "INFO" "step=validate_env"
      validate_env
      if [[ -n "${2:-}" ]]; then
        log "INFO" "step=sync_mentor_voice_sample"
        sync_mentor_voice_sample "${2}"
      fi
      log "INFO" "step=ensure_ironclaw_home_writable"
      ensure_ironclaw_home_writable
      log "INFO" "step=auto_bootstrap_mentor_voice_if_enabled"
      auto_bootstrap_mentor_voice_if_enabled
      log "INFO" "step=compose_up_edge_services"
      compose_local up -d caddy cloudflared
      log "INFO" "step=configure_local_tunnel_url"
      configure_local_tunnel_url
      log "INFO" "step=compose_up"
      compose_local up -d
      log "INFO" "step=compose_recreate_ironclaw_for_env"
      compose_local up -d --force-recreate --no-deps ironclaw
      log "INFO" "step=smoke_local"
      smoke_local
      log "INFO" "step=ensure_mcp_servers_registered"
      local mcp_changed=0
      if ensure_camoufox_mcp_registered; then
        mcp_changed=1
      fi
      if ensure_mentor_mcp_registered; then
        mcp_changed=1
      fi
      if [[ "$mcp_changed" -eq 1 ]]; then
        log "INFO" "step=restart_ironclaw_for_mcp"
        compose_local restart ironclaw
        wait_for_ironclaw
      fi
      if telegram_configured; then
        log "INFO" "step=set_telegram_bot_commands"
        if ! (set_telegram_bot_commands); then
          echo "[up] warning: telegram command registration failed; continuing"
        fi
        log "INFO" "step=auto_bind_telegram_allowed_chat_id"
        auto_bind_telegram_allowed_chat_id
      else
        echo "[up] telegram not configured in .env (TELEGRAM_BOT_TOKEN), skipping webhook/commands"
      fi
      echo "[up] done"
      echo "IronClaw URL: $(api_base_url)"
      echo "Proxy URL: http://localhost:$(read_env_var LOCAL_HTTP_PORT)"
      ;;

    restart)
      require_cmd docker
      log "INFO" "step=ensure_env_file"
      ensure_env_file
      log "INFO" "step=validate_env"
      validate_env
      if [[ -n "${2:-}" ]]; then
        log "INFO" "step=sync_mentor_voice_sample"
        sync_mentor_voice_sample "${2}"
      fi
      log "INFO" "step=compose_down"
      compose_local down
      log "INFO" "step=ensure_ironclaw_home_writable"
      ensure_ironclaw_home_writable
      log "INFO" "step=auto_bootstrap_mentor_voice_if_enabled"
      auto_bootstrap_mentor_voice_if_enabled
      log "INFO" "step=compose_up_edge_services"
      compose_local up -d caddy cloudflared
      log "INFO" "step=configure_local_tunnel_url"
      configure_local_tunnel_url
      log "INFO" "step=compose_up"
      compose_local up -d
      log "INFO" "step=compose_recreate_ironclaw_for_env"
      compose_local up -d --force-recreate --no-deps ironclaw
      log "INFO" "step=smoke_local"
      smoke_local
      log "INFO" "step=ensure_mcp_servers_registered"
      local mcp_changed=0
      if ensure_camoufox_mcp_registered; then
        mcp_changed=1
      fi
      if ensure_mentor_mcp_registered; then
        mcp_changed=1
      fi
      if [[ "$mcp_changed" -eq 1 ]]; then
        log "INFO" "step=restart_ironclaw_for_mcp"
        compose_local restart ironclaw
        wait_for_ironclaw
      fi
      if telegram_configured; then
        log "INFO" "step=set_telegram_bot_commands"
        if ! (set_telegram_bot_commands); then
          echo "[restart] warning: telegram command registration failed; continuing"
        fi
        log "INFO" "step=auto_bind_telegram_allowed_chat_id"
        auto_bind_telegram_allowed_chat_id
      else
        echo "[restart] telegram not configured in .env (TELEGRAM_BOT_TOKEN), skipping webhook/commands"
      fi
      echo "[restart] done"
      echo "IronClaw URL: $(api_base_url)"
      echo "Proxy URL: http://localhost:$(read_env_var LOCAL_HTTP_PORT)"
      ;;

    down)
      require_cmd docker
      log "INFO" "step=ensure_env_file"
      ensure_env_file
      compose_local down
      ;;

    health)
      require_cmd docker
      log "INFO" "step=ensure_env_file"
      ensure_env_file
      echo "[health] compose services"
      compose_local ps
      echo "[health] ironclaw"
      curl -sS "$(api_base_url)/healthz" || curl -sS "$(api_base_url)/"
      echo
      echo "[health] camoufox-tool"
      compose_local exec -T camoufox-tool node -e "fetch('http://127.0.0.1:8788/healthz').then(async r=>{console.log(await r.text()); if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"
      echo "[health] camoufox-mcp"
      compose_local exec -T camoufox-mcp node -e "fetch('http://127.0.0.1:8790/healthz').then(async r=>{console.log(await r.text()); if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"
      echo "[health] mentor-mcp"
      compose_local exec -T mentor-mcp node -e "fetch('http://127.0.0.1:8791/healthz').then(async r=>{console.log(await r.text()); if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"
      echo "[health] registered MCP servers"
      compose_local run --rm --no-deps ironclaw mcp list || true
      ;;

    logs)
      require_cmd docker
      log "INFO" "step=ensure_env_file"
      ensure_env_file
      local service="${2:-}"
      if [[ -n "$service" ]]; then
        compose_local logs -f "$service"
      else
        compose_local logs -f
      fi
      ;;

    shell)
      require_cmd docker
      log "INFO" "step=ensure_env_file"
      ensure_env_file
      compose_local exec agent-sandbox bash
      ;;

    webhook:set)
      require_cmd docker
      log "INFO" "step=ensure_env_file"
      ensure_env_file
      log "INFO" "step=validate_env"
      validate_env
      log "INFO" "step=validate_telegram_env"
      validate_telegram_env
      log "INFO" "step=set_telegram_webhook"
      set_telegram_webhook "local"
      log "INFO" "step=set_telegram_bot_commands"
      set_telegram_bot_commands
      ;;

    telegram:commands)
      require_cmd docker
      log "INFO" "step=ensure_env_file"
      ensure_env_file
      log "INFO" "step=validate_telegram_env"
      validate_telegram_env
      log "INFO" "step=set_telegram_bot_commands"
      set_telegram_bot_commands
      ;;

    telegram:autobind)
      require_cmd docker
      log "INFO" "step=ensure_env_file"
      ensure_env_file
      log "INFO" "step=validate_telegram_env"
      validate_telegram_env
      log "INFO" "step=wait_for_ironclaw"
      wait_for_ironclaw
      log "INFO" "step=auto_bind_telegram_allowed_chat_id"
      auto_bind_telegram_allowed_chat_id
      ;;

    mentor:clone)
      require_cmd curl
      log "INFO" "step=ensure_env_file"
      ensure_env_file
      log "INFO" "step=bootstrap_mentor_voice_context"
      bootstrap_mentor_voice_context "${2:-}"
      ;;

    smoke)
      require_cmd docker
      log "INFO" "step=ensure_env_file"
      ensure_env_file
      smoke_local
      ;;

    deploy:vps)
      require_cmd docker
      log "INFO" "step=ensure_env_file"
      ensure_env_file
      log "INFO" "step=validate_env"
      validate_env
      deploy_vps_release
      ;;

    rollback:vps)
      log "INFO" "step=ensure_env_file"
      ensure_env_file
      rollback_vps_release
      ;;

    -h|--help|help|"")
      usage
      ;;

    *)
      echo "ERROR: unknown command: $cmd" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
