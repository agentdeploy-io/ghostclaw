# Ghostclaw Runbook (Official IronClaw + Camoufox)
This repo is operated through one script only:

```bash
./scripts/ghostclaw.sh
```

Everything else is implementation detail.

## Architecture

Services in the stack:
- `postgres` (`pgvector/pgvector:pg16`) for IronClaw state and memory
- `ironclaw` official runtime built from `IRONCLAW_GIT_URL` + `IRONCLAW_GIT_REF`
- `camoufox-tool` browser automation engine
- `camoufox-mcp` MCP adapter that registers Camoufox tools into IronClaw tool registry
- `caddy` reverse proxy
- `cloudflared` local tunnel for webhook mode
- `agent-sandbox` interactive container for development shell access

Compose files:
- `docker-compose.yml` (base)
- `docker-compose.local.yml` (local ports + tunnel)
- `docker-compose.vps.yml` (VPS hardening + 80/443)

## Resource Requirements

Local minimum:
- 4 vCPU
- 8 GB RAM
- 30 GB free disk

Local recommended:
- 8 vCPU
- 16 GB RAM
- 60 GB free disk

Hostinger VPS minimum:
- 4 vCPU
- 8 GB RAM
- 80 GB SSD
- Ubuntu 22.04+

Notes:
- First source build is heavy (Rust + Playwright layers).
- Docker cache/image footprint can exceed 20 GB.

## Quickstart

```bash
cd "/Users/mac/Documents/ironclaw"
./scripts/ghostclaw.sh init
./scripts/ghostclaw.sh onboard
./scripts/ghostclaw.sh up
./scripts/ghostclaw.sh health
```

Expected output markers:
- `init`: `[init] wrote .../.env`
- `onboard`: starts dependencies then enters interactive onboarding inside container
- `up`: `[smoke] local stack healthy` and, when `TELEGRAM_BOT_TOKEN` is configured, webhook registration
- `health`: prints compose status + IronClaw/Camoufox health payload

## Command Reference

```bash
./scripts/ghostclaw.sh init
./scripts/ghostclaw.sh onboard
./scripts/ghostclaw.sh up
./scripts/ghostclaw.sh restart
./scripts/ghostclaw.sh down
./scripts/ghostclaw.sh health
./scripts/ghostclaw.sh logs
./scripts/ghostclaw.sh logs ironclaw
./scripts/ghostclaw.sh shell
./scripts/ghostclaw.sh webhook:set
./scripts/ghostclaw.sh smoke
./scripts/ghostclaw.sh deploy:vps
./scripts/ghostclaw.sh rollback:vps
```

## Camoufox Tools (Auto-Wired)

- `up` and `restart` auto-register MCP server `camoufox -> http://camoufox-mcp:8790`
- IronClaw loads these tools into the registry with prefix `camoufox_`
- Expected tool names include `camoufox_browser.session_new`, `camoufox_browser.goto`, `camoufox_browser.click`, `camoufox_browser.fill`, `camoufox_browser.press`, `camoufox_browser.click_xy`, `camoufox_browser.wait_for_selector`, `camoufox_browser.wait`, `camoufox_browser.screenshot`, `camoufox_browser.session_close`

Verify registry wiring:

```bash
TOKEN="$(grep "^GATEWAY_AUTH_TOKEN=" .env | cut -d= -f2-)"
curl -sS http://localhost:8082/api/extensions/tools -H "Authorization: Bearer ${TOKEN}"
```

If tools are not visible after a plain `docker compose restart`, run:

```bash
./scripts/ghostclaw.sh restart
```

If registration fails with HTTPS validation, rebuild ironclaw image once:

```bash
docker compose --env-file .env -f docker-compose.yml -f docker-compose.local.yml build --no-cache ironclaw
./scripts/ghostclaw.sh restart
```

## Telegram Webhook Flow

Local mode:
- `up` starts `cloudflared`
- if `TELEGRAM_BOT_TOKEN` is configured, webhook URL is parsed from tunnel logs and `setWebhook` is called against `/webhook/telegram`
- Caddy routes `/webhook/*` to IronClaw HTTP channel on port `8090`, while UI/API stays on gateway port `8080`
- if token is missing/placeholder, stack still starts and webhook step is skipped

Manual local reset:

```bash
./scripts/ghostclaw.sh webhook:set
```

VPS mode:
- uses `https://$DOMAIN$TELEGRAM_WEBHOOK_PATH`
- webhook is set during `deploy:vps` when `TELEGRAM_BOT_TOKEN` is configured

## VPS Deployment

Set VPS variables in `.env`:
- `VPS_HOST`
- `VPS_USER` (default `root`)
- `VPS_SSH_KEY` (optional)
- `VPS_REMOTE_DIR` (default `/opt/ghostclaw`)
- `DOMAIN`

Deploy:

```bash
./scripts/ghostclaw.sh deploy:vps
```

Rollback:

```bash
./scripts/ghostclaw.sh rollback:vps
```

## Troubleshooting

### IronClaw image build fails

Cause:
- build context or ref mismatch, or Rust/dependency incompatibility for the selected IronClaw ref.

Fix in this repo:
- `docker/Dockerfile.ironclaw` builds IronClaw from source with Rust 1.92 and patches `libsql` features for cloud TLS sync compatibility.

If still failing:
- verify `.env` `IRONCLAW_GIT_URL` and `IRONCLAW_GIT_REF`
- rebuild without cache:

```bash
docker compose --env-file .env -f docker-compose.yml -f docker-compose.local.yml build --no-cache ironclaw
```

### libSQL onboarding or Turso sync fails

Check:
- `/home/ironclaw/.ironclaw` is writable in container (entrypoint now fixes ownership on startup)
- Turso URL format is `libsql://your-db.turso.io`
- token is valid and not expired
- image was rebuilt after Dockerfile changes:

```bash
docker compose --env-file .env -f docker-compose.yml -f docker-compose.local.yml build ironclaw
```

If you still see `tls feature is disabled`:
- confirm image is rebuilt from latest `docker/Dockerfile.ironclaw`
- restart with rebuild:

```bash
docker compose --env-file .env -f docker-compose.yml -f docker-compose.local.yml up -d --build ironclaw
```

### Webhook setup fails

Check:
- if using Telegram: `TELEGRAM_BOT_TOKEN` and `TELEGRAM_WEBHOOK_SECRET` are non-placeholder
- tunnel is up (`cloudflared` service running)
- BotFather token is valid

Inspect tunnel logs:

```bash
docker compose --env-file .env -f docker-compose.yml -f docker-compose.local.yml logs cloudflared
```

### Gateway restart instability

Cause:
- gateway and webhook HTTP server can conflict if both bind `8080`.

Fix in this repo:
- gateway is pinned to `8080`
- webhook HTTP channel is pinned to `8090`
- Caddy forwards `/webhook/*` to `8090` and all other traffic to `8080`

If startup loops still happen after a crash, cycle the full stack so dependencies rebind cleanly:

```bash
./scripts/ghostclaw.sh down
./scripts/ghostclaw.sh up
```

### Port conflicts

Ports are fixed for deterministic behavior:
- `LOCAL_HTTP_PORT=8080`
- `LOCAL_HTTPS_PORT=8443`
- `IRONCLAW_HOST_PORT=8082`

If one of these is already occupied by another process, free that port and rerun `./scripts/ghostclaw.sh up`.

### Slow builds

Expected on first run due source build + browser layers.

Mitigations:
- allocate more Docker Desktop CPU/RAM
- avoid frequent `--no-cache` builds
- keep `IRONCLAW_GIT_REF` stable to maximize cache reuse

## Security Notes

- Secrets are stored in `.env` (mode `600`)
- Never commit `.env`
- Rotate `INTERNAL_API_TOKEN`, `TELEGRAM_WEBHOOK_SECRET`, and model keys after tests
