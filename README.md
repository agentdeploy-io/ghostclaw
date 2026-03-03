# Ghostclaw Template

Production-grade one-click deploy for Ironclaw + Camoufox browser automation.

## Quick Start

```bash
# 1. Initialize
./scripts/ghostclaw.sh init

# 2. Onboard (configure API keys, Telegram, etc.)
./scripts/ghostclaw.sh onboard

# 3. Start
./scripts/ghostclaw.sh up
```

## Features

- **One-Click Deploy**: Local development or Hostinger VPS
- **Browser Automation**: Camoufox integration with anti-detection
- **MCP Server Support**: Pluggable AI services (mentor, context7, etc.)
- **Telegram Integration**: Built-in bot with slash commands
- **Secure by Default**: Non-root containers, resource limits, firewall rules

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Docker Compose Stack                    │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────┐ │
│  │  caddy      │  │  ironclaw    │  │  camoufox-tool      │ │
│  │  (reverse   │  │  (gateway)   │  │  (browser API)      │ │
│  │   proxy)    │  │              │  │                     │ │
│  └─────────────┘  └──────────────┘  └─────────────────────┘ │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────┐ │
│  │  camoufox-  │  │  mentor-mcp  │  │  redis              │ │
│  │  mcp        │  │  (optional)  │  │  (queue/cache)      │ │
│  └─────────────┘  └──────────────┘  └─────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Command Reference

```bash
# Setup
./scripts/ghostclaw.sh init          # Generate .env file
./scripts/ghostclaw.sh onboard       # Interactive configuration

# Lifecycle
./scripts/ghostclaw.sh up            # Start all services
./scripts/ghostclaw.sh down          # Stop all services
./scripts/ghostclaw.sh restart       # Full restart

# Deployment
./scripts/ghostclaw.sh deploy:vps    # Deploy to Hostinger VPS
./scripts/ghostclaw.sh rollback:vps  # Rollback to previous release

# Telegram
./scripts/ghostclaw.sh telegram:commands  # Register slash commands
./scripts/ghostclaw.sh webhook:set        # Set webhook URL

# MCP Servers
./scripts/ghostclaw.sh mcp:add <name> <url>   # Register MCP server
./scripts/ghostclaw.sh mcp:remove <name>      # Remove MCP server
./scripts/ghostclaw.sh mcp:list               # List registered servers
```

## Configuration

Edit `.env` after running `init`:

| Variable | Description | Default |
|----------|-------------|---------|
| `MAIN_LLM_API_KEY` | API key for main LLM | Required |
| `SUB_LLM_API_KEY` | API key for sub-agent LLM | Required |
| `TELEGRAM_BOT_TOKEN` | Telegram bot token | Optional |
| `TELEGRAM_WEBHOOK_SECRET` | Secret for webhook validation | Auto-generated |
| `IRONCLAW_GIT_URL` | Ironclaw repository URL | nearai/ironclaw |
| `IRONCLAW_GIT_REF` | Ironclaw branch/tag | v0.12.0 |

## Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| Local (macOS/Linux) | ✅ | Requires Docker Desktop or Docker Engine |
| Hostinger VPS | ✅ | One-click deploy via SSH |
| Railway/Render | ⚠️ | Requires custom configuration |

## Requirements

- Docker Engine 24+
- Docker Compose 2.20+
- Node.js 20+ (for local development)
- Redis (included in Docker stack)
- 4GB RAM minimum (8GB recommended)

## Security

- Secrets stored in `.env` (mode 600)
- Non-root container execution
- Read-only root filesystem where possible
- Resource limits (CPU, memory, pids)
- Firewall allows only 22/80/443

## Troubleshooting

### Telegram Commands Not Working

```bash
# Re-register commands
./scripts/ghostclaw.sh telegram:commands

# Check webhook status
curl -X POST "https://api.telegram.org/bot<TOKEN>/getWebhookInfo"
```

### MCP Server Not Responding

```bash
# Check health
curl http://localhost:8791/healthz

# Restart MCP server
docker compose restart mentor-mcp
```

### VPS Deploy Fails

```bash
# Check SSH connection
ssh -i <KEY> <USER>@<HOST>

# Check remote Docker
ssh -i <KEY> <USER>@<HOST> "docker version"
```

## License

MIT
