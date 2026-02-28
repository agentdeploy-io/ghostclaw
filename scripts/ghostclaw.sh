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

  set_env_var_if_missing "IRONCLAW_GIT_URL" "replace_with_official_ironclaw_git_url"
  set_env_var_if_missing "IRONCLAW_GIT_REF" "replace_with_git_tag_or_commit"
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

  set_env_var_if_missing "TELEGRAM_BOT_TOKEN" "replace_with_telegram_bot_token"
  set_env_var_if_missing "TELEGRAM_WEBHOOK_SECRET" "$(openssl rand -hex 32)"
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

ensure_camoufox_mcp_registered() {
  if camoufox_mcp_registered; then
    echo "[mcp] camoufox MCP already registered"
    return 1
  fi

  compose_local run --rm --no-deps ironclaw mcp add camoufox http://camoufox-mcp:8790 --description "Camoufox browser automation bridge" >/dev/null
  echo "[mcp] registered camoufox MCP server"
  return 0
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

# Ensure Camoufox MCP tools are registered in official IronClaw tool registry
$SUDO docker compose --env-file .env -f docker-compose.yml -f docker-compose.vps.yml run --rm --no-deps ironclaw \
  mcp add camoufox http://camoufox-mcp:8790 --description "Camoufox browser automation bridge" >/dev/null || true
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
  onboard            Run official `ironclaw onboard` inside container
  up                 Start local stack (Telegram webhook auto-configures when TELEGRAM_BOT_TOKEN is configured)
  restart            Full local restart (down + up + smoke)
  down               Stop local stack
  health             Show local service and endpoint health
  logs [service]     Tail logs for all services or a single service
  shell              Open interactive shell in agent-sandbox
  webhook:set        Set Telegram webhook for local tunnel (single bot token)
  smoke              Validate local stack readiness
  deploy:vps         Deploy stack to Hostinger VPS
  rollback:vps       Roll back VPS to previous release
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
      compose_local up -d camoufox-tool camoufox-mcp
      log "INFO" "step=run_onboard_wizard"
      compose_local run --rm ironclaw onboard
      ;;

    up)
      require_cmd docker
      log "INFO" "step=ensure_env_file"
      ensure_env_file
      log "INFO" "step=validate_env"
      validate_env
      log "INFO" "step=ensure_ironclaw_home_writable"
      ensure_ironclaw_home_writable
      log "INFO" "step=compose_up"
      compose_local up -d
      log "INFO" "step=smoke_local"
      smoke_local
      log "INFO" "step=ensure_camoufox_mcp_registered"
      local mcp_changed=0
      if ensure_camoufox_mcp_registered; then
        mcp_changed=1
      fi
      if [[ "$mcp_changed" -eq 1 ]]; then
        log "INFO" "step=restart_ironclaw_for_mcp"
        compose_local restart ironclaw
        wait_for_ironclaw
      fi
      if telegram_configured; then
        log "INFO" "step=set_telegram_webhook"
        if ! (set_telegram_webhook "local"); then
          echo "[up] warning: telegram webhook setup failed; continuing"
        fi
      else
        echo "[up] telegram not configured, skipping webhook setup"
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
      log "INFO" "step=compose_down"
      compose_local down
      log "INFO" "step=ensure_ironclaw_home_writable"
      ensure_ironclaw_home_writable
      log "INFO" "step=compose_up"
      compose_local up -d
      log "INFO" "step=smoke_local"
      smoke_local
      log "INFO" "step=ensure_camoufox_mcp_registered"
      local mcp_changed=0
      if ensure_camoufox_mcp_registered; then
        mcp_changed=1
      fi
      if [[ "$mcp_changed" -eq 1 ]]; then
        log "INFO" "step=restart_ironclaw_for_mcp"
        compose_local restart ironclaw
        wait_for_ironclaw
      fi
      if telegram_configured; then
        log "INFO" "step=set_telegram_webhook"
        if ! (set_telegram_webhook "local"); then
          echo "[restart] warning: telegram webhook setup failed; continuing"
        fi
      else
        echo "[restart] telegram not configured, skipping webhook setup"
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
