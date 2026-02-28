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
- `camoufox-tool` browser automation service (`browser.goto`, `browser.click`, `browser.fill`, `browser.press`, `browser.click_xy`, `browser.wait_for_selector`, `browser.wait`, `browser.screenshot`)
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

## Telegram Webhook Flow

Local mode:
- `up` starts `cloudflared`
- if `TELEGRAM_BOT_TOKEN` is configured, webhook URL is parsed from tunnel logs and `setWebhook` is called
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

### Port conflicts

`init` auto-selects free ports for:
- `LOCAL_HTTP_PORT`
- `LOCAL_HTTPS_PORT`
- `IRONCLAW_HOST_PORT`

Override in `.env` if needed.

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
