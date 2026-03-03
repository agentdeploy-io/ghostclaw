# Lippyclaw Implementation Plan

## Overview

This document provides a step-by-step implementation plan for transforming the current ghostclaw repository into a standalone lippyclaw product with clear separation from the ghostclaw deployment wrapper.

---

## Phase 1: Repository Rebranding (Day 1)

### 1.1 Update Package Configuration

**File: `package.json`**

Change the package identity from ghostclaw-template to lippyclaw:

```json
{
  "name": "lippyclaw",
  "version": "1.0.0",
  "private": false,
  "description": "Self-contained AI automation platform with mentor and voice capabilities",
  "main": "dist/index.js",
  "bin": {
    "lippyclaw": "./dist/cli.js"
  },
  "files": [
    "dist",
    "mentor-mcp",
    "camoufox-mcp",
    "mentor"
  ],
  "engines": {
    "node": ">=20.11.0"
  },
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "start": "node dist/index.js",
    "start:worker": "node dist/worker.js",
    "start:mentor-mcp": "node mentor-mcp/server.mjs",
    "start:camoufox-mcp": "node camoufox-mcp/server.mjs",
    "start:all": "concurrently \"npm:start\" \"npm:start:worker\" \"npm:start:mentor-mcp\" \"npm:start:camoufox-mcp\"",
    "dev": "tsx watch src/index.ts",
    "dev:worker": "tsx watch src/worker.ts",
    "dev:all": "concurrently \"npm:dev\" \"npm:dev:worker\" \"npm:start:mentor-mcp\" \"npm:start:camoufox-mcp\"",
    "typecheck": "tsc --noEmit -p tsconfig.json",
    "prepare": "npm run build"
  },
  "dependencies": {
    "bullmq": "^5.12.0",
    "camoufox-js": "^0.9.1",
    "dotenv": "^16.4.5",
    "fastify": "^5.1.0",
    "ioredis": "^5.4.2",
    "pino": "^9.4.0",
    "playwright": "^1.49.1",
    "zod": "^3.23.8"
  },
  "devDependencies": {
    "@types/node": "^22.10.2",
    "concurrently": "^8.2.2",
    "tsx": "^4.19.2",
    "typescript": "^5.7.2"
  }
}
```

### 1.2 Update Environment Template

**File: `.env.example`**

Reorganize and add new platform configuration variables:

```bash
# ===========================================
# LIPPYCLAW CONFIGURATION
# ===========================================

# Core runtime
NODE_ENV=development
HOST=0.0.0.0
PORT=8787
LOG_LEVEL=info

# Security for internal API routes
INTERNAL_API_TOKEN=

# Redis / queue
REDIS_URL=redis://localhost:6379
WORKER_CONCURRENCY=2

# Artifact storage
ARTIFACT_DIR=./data/artifacts

# ===========================================
# LLM CONFIGURATION (Required)
# ===========================================

# Main LLM for primary agent
MAIN_LLM_BASE_URL=https://llm.chutes.ai/v1
MAIN_LLM_API_KEY=
MAIN_LLM_MODEL=Qwen/Qwen3.5-397B-A17B-TEE

# Sub-agent LLM for secondary tasks
SUB_LLM_BASE_URL=https://llm.chutes.ai/v1
SUB_LLM_API_KEY=
SUB_LLM_MODEL=MiniMaxAI/MiniMax-M2.5-TEE

LLM_REQUEST_TIMEOUT_MS=120000

# ===========================================
# MENTOR CONFIGURATION (Optional - Enabled by Default)
# ===========================================

MENTOR_NAME=Lippyclaw Mentor
MENTOR_PERSONA_FILE=./mentor/persona.md
MENTOR_MEMORY_FILE=./data/mentor/memory.json
MENTOR_MEMORY_WINDOW=14
MENTOR_LLM_BASE_URL=https://llm.chutes.ai/v1
MENTOR_LLM_MODEL=MiniMaxAI/MiniMax-M2.5-TEE
MENTOR_LLM_API_KEY=

# Voice configuration
ENABLE_MENTOR_VOICE=true
MENTOR_VOICE_API_KEY=
MENTOR_CHUTES_VOICE_MODE=run_api
MENTOR_CHUTES_RUN_ENDPOINT=https://llm.chutes.ai/v1/run
MENTOR_CHUTES_WHISPER_MODEL=openai/whisper-large-v3-turbo
MENTOR_CHUTES_CSM_MODEL=sesame/csm-1b
MENTOR_CHUTES_KOKORO_MODEL=hexgrad/Kokoro-82M
MENTOR_CHUTES_ENABLE_KOKORO_FALLBACK=true
MENTOR_VOICE_SAMPLE_PATH=./mentor/master-voice.wav
MENTOR_VOICE_CONTEXT_PATH=./data/mentor/voice_context.txt
MENTOR_VOICE_AUTO_TRANSCRIBE=true

# ===========================================
# PLATFORM INTEGRATIONS (Optional)
# ===========================================

# Telegram
ENABLE_TELEGRAM=false
TELEGRAM_BOT_TOKEN=
TELEGRAM_WEBHOOK_SECRET=
TELEGRAM_ALLOWED_CHAT_IDS=

# Slack
ENABLE_SLACK=false
SLACK_BOT_TOKEN=
SLACK_SIGNING_SECRET=
SLACK_APP_TOKEN=

# Discord
ENABLE_DISCORD=false
DISCORD_BOT_TOKEN=
DISCORD_CLIENT_ID=

# WhatsApp
ENABLE_WHATSAPP=false
WHATSAPP_PHONE_NUMBER_ID=
WHATSAPP_ACCESS_TOKEN=
WHATSAPP_VERIFY_TOKEN=

# ===========================================
# BROWSER AUTOMATION (Optional)
# ===========================================

BROWSER_PROVIDER=camoufox
BROWSER_HEADLESS=true
BROWSER_DEFAULT_TIMEOUT_MS=25000
BROWSER_CHALLENGE_KEYWORDS=captcha,verify you are human,security check
BROWSER_EXECUTABLE_PATH=

# Camoufox-specific
CAMOUFOX_WS_ENDPOINT=
CAMOUFOX_CONNECT_TIMEOUT_MS=30000

# ===========================================
# DEPLOYMENT (Optional - for Docker)
# ===========================================

DOMAIN=localhost
ACME_EMAIL=
DATABASE_URL=
SECRETS_MASTER_KEY=
GATEWAY_AUTH_TOKEN=

# Ironclaw fork (if using Docker with Ironclaw runtime)
IRONCLAW_GIT_URL=https://github.com/lippycoin/lippyclaw
IRONCLAW_GIT_REF=main

# PostgreSQL (for Ironclaw runtime)
POSTGRES_DB=lippyclaw
POSTGRES_USER=lippyclaw
POSTGRES_PASSWORD=

# Telegram webhook path
TELEGRAM_WEBHOOK_PATH=/telegram/webhook

# Tunnel mode for local development
TUNNEL_MODE=cloudflared

# VPS deployment (for ghostclaw wrapper)
VPS_HOST=
VPS_USER=root
VPS_SSH_KEY=
VPS_REMOTE_DIR=/opt/lippyclaw

# Local ports
LOCAL_HTTP_PORT=8080
LOCAL_HTTPS_PORT=8443
IRONCLAW_HOST_PORT=8082
```

### 1.3 Create New README

**File: `README.md`**

Replace the ghostclaw-focused README with lippyclaw branding:

```markdown
# Lippyclaw

Self-contained AI automation platform with mentor and voice capabilities out of the box.

## Quick Start

### Native Installation (Recommended for Development)

```bash
# 1. Clone
git clone https://github.com/lippycoin/lippyclaw
cd lippyclaw

# 2. Install dependencies
npm install

# 3. Configure
cp .env.example .env
# Edit .env with your API keys

# 4. Start Redis (required)
brew install redis && brew services start redis  # macOS
# OR
docker run -d -p 6379:6379 redis:7

# 5. Run
npm run dev           # Main API
npm run dev:worker    # Background worker
```

### Docker Installation (Production)

```bash
git clone https://github.com/lippycoin/lippyclaw
cd lippyclaw
cp .env.example .env
# Edit .env
docker compose up -d
```

## Features

- **Multi-Platform Support**: Telegram, Slack, Discord, WhatsApp
- **Built-in Mentor**: Chat and voice capabilities via MCP
- **Browser Automation**: Camoufox integration for web tasks
- **Voice TTS/STT**: Whisper transcription + CSM voice cloning
- **Flexible Deployment**: Native Node.js or Docker

## Documentation

- [Architecture](plans/lippyclaw-standalone-architecture.md)
- [Implementation Plan](plans/lippyclaw-implementation-plan.md)

## License

MIT
```

---

## Phase 2: Platform Integrations (Days 2-3)

### 2.1 Create Slack Integration

**File: `src/lib/slack.ts`** (NEW)

```typescript
import { createEventAdapter } from "@slack/events-api";
import { WebClient } from "@slack/web-api";
import { logger } from "../logger.js";

export interface SlackConfig {
  signingSecret: string;
  botToken: string;
  appToken: string;
}

export interface SlackMessage {
  channelId: string;
  userId: string;
  text: string;
  threadTs?: string;
}

let slackEvents: ReturnType<typeof createEventAdapter> | null = null;
let slackClient: WebClient | null = null;

export function initializeSlack(config: SlackConfig): void {
  slackEvents = createEventAdapter(config.signingSecret);
  slackClient = new WebClient(config.botToken);
  logger.info({ channel: "slack" }, "Slack integration initialized");
}

export async function sendSlackMessage(
  channelId: string,
  text: string,
  threadTs?: string,
): Promise<void> {
  if (!slackClient) {
    throw new Error("Slack not initialized");
  }

  await slackClient.chat.postMessage({
    channel: channelId,
    text,
    thread_ts: threadTs,
  });
}

export function getSlackEventHandler() {
  if (!slackEvents) {
    throw new Error("Slack not initialized");
  }
  return slackEvents;
}

export { slackClient };
```

### 2.2 Create Discord Integration

**File: `src/lib/discord.ts`** (NEW)

```typescript
import { Client, GatewayIntentBits, Partials } from "discord.js";
import { logger } from "../logger.js";

export interface DiscordConfig {
  botToken: string;
  clientId: string;
}

let discordClient: Client | null = null;

export function initializeDiscord(config: DiscordConfig): Client {
  discordClient = new Client({
    intents: [
      GatewayIntentBits.Guilds,
      GatewayIntentBits.GuildMessages,
      GatewayIntentBits.MessageContent,
      GatewayIntentBits.DirectMessages,
    ],
    partials: [Partials.Channel],
  });

  discordClient.once("ready", () => {
    logger.info({ userId: discordClient?.user?.id }, "Discord bot ready");
  });

  discordClient.login(config.botToken);
  return discordClient;
}

export async function sendDiscordMessage(
  channelId: string,
  text: string,
): Promise<void> {
  if (!discordClient) {
    throw new Error("Discord not initialized");
  }

  const channel = await discordClient.channels.fetch(channelId);
  if (channel?.isTextBased()) {
    await channel.send(text);
  }
}

export { discordClient };
```

### 2.3 Create WhatsApp Integration

**File: `src/lib/whatsapp.ts`** (NEW)

```typescript
import { logger } from "../logger.js";

export interface WhatsAppConfig {
  phoneNumberId: string;
  accessToken: string;
  verifyToken: string;
}

const BASE_URL = "https://graph.facebook.com/v18.0";

export async function sendWhatsAppMessage(
  phoneNumberId: string,
  accessToken: string,
  recipientId: string,
  text: string,
): Promise<void> {
  const url = `${BASE_URL}/${phoneNumberId}/messages`;

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      messaging_product: "whatsapp",
      to: recipientId,
      type: "text",
      text: { body: text },
    }),
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`WhatsApp API error: ${error}`);
  }

  logger.info({ recipientId }, "WhatsApp message sent");
}

export async function verifyWhatsAppWebhook(
  mode: string,
  token: string,
  verifyToken: string,
): Promise<string | null> {
  if (mode === "subscribe" && token === verifyToken) {
    return token;
  }
  return null;
}
```

### 2.4 Update Main Index with Platform Support

**File: `src/index.ts`**

Add new webhook handlers for Slack, Discord, and WhatsApp alongside the existing Telegram handler.

---

## Phase 3: Update Docker Configuration (Day 4)

### 3.1 Rename Dockerfiles

Update Docker file references to use lippyclaw naming:

```bash
# Rename files
mv docker/Dockerfile.ironclaw docker/Dockerfile.lippyclaw
mv docker/Dockerfile.mentor-mcp docker/Dockerfile.mentor-mcp  # stays same
mv docker/Dockerfile.camoufox-mcp docker/Dockerfile.camoufox-mcp  # stays same
```

### 3.2 Update docker-compose.yml

**File: `docker-compose.yml`**

Change service names and references from ghostclaw to lippyclaw:

```yaml
name: lippyclaw

services:
  lippyclaw:
    build:
      context: .
      dockerfile: docker/Dockerfile.lippyclaw
    # ... rest of configuration
```

---

## Phase 4: Create Ghostclaw Wrapper (Day 5)

### 4.1 Ghostclaw Repository Structure

Create a SEPARATE repository for ghostclaw:

```
ghostclaw/
├── README.md                 # "Generic AI deployment wrapper"
├── scripts/
│   └── ghostclaw.sh          # Main orchestration script
├── docker/
│   ├── Dockerfile.lippyclaw  # Wraps lippyclaw npm package
│   └── ...
├── docker-compose.yml        # Production compose
├── package.json              # { "dependencies": { "lippyclaw": "^1.0.0" } }
└── .env.example
```

### 4.2 Ghostclaw package.json

```json
{
  "name": "ghostclaw",
  "version": "1.0.0",
  "description": "Generic AI deployment wrapper - works with lippyclaw and other AI services",
  "dependencies": {
    "lippyclaw": "^1.0.0"
  },
  "scripts": {
    "start": "node -r lippyclaw/dist/index.js"
  }
}
```

---

## Phase 5: Documentation (Day 6)

### 5.1 Create Platform Setup Guides

**File: `docs/platforms/telegram.md`**
**File: `docs/platforms/slack.md`**
**File: `docs/platforms/discord.md`**
**File: `docs/platforms/whatsapp.md`**

Each guide should include:
- Prerequisites
- Step-by-step setup
- Environment variables required
- Testing instructions
- Troubleshooting

### 5.2 Create Deployment Guides

**File: `docs/deployment/native.md`**
**File: `docs/deployment/docker.md`**
**File: `docs/deployment/railway.md`**
**File: `docs/deployment/vps.md`**

---

## Phase 6: Testing & Validation (Day 7)

### 6.1 Test Checklist

| Test | Description | Status |
|------|-------------|--------|
| Native start | `npm install && npm run dev` works | [ ] |
| Docker start | `docker compose up -d` works | [ ] |
| Telegram webhook | Messages received and processed | [ ] |
| Slack integration | Slash commands work | [ ] |
| Discord integration | Bot responds to messages | [ ] |
| WhatsApp integration | Messages sent/received | [ ] |
| Mentor chat | `/mentor` command works | [ ] |
| Mentor voice | Voice responses generated | [ ] |
| Browser automation | `/run` command queues jobs | [ ] |
| MCP registration | Servers auto-register on startup | [ ] |

---

## File Changes Summary

### Files to Create

| File | Purpose |
|------|---------|
| `src/lib/slack.ts` | Slack bot integration |
| `src/lib/discord.ts` | Discord bot integration |
| `src/lib/whatsapp.ts` | WhatsApp Business integration |
| `docs/platforms/*.md` | Platform setup guides |
| `docs/deployment/*.md` | Deployment guides |

### Files to Modify

| File | Changes |
|------|---------|
| `package.json` | Rename to lippyclaw, add scripts |
| `.env.example` | Reorganize, add platform vars |
| `README.md` | Complete rewrite for lippyclaw |
| `src/index.ts` | Add new webhook handlers |
| `src/config.ts` | Add platform configuration |
| `docker-compose.yml` | Rename services |
| `docker/Dockerfile.*` | Rename and update |

### Files to Move (to ghostclaw repo)

| File | New Location |
|------|--------------|
| `scripts/ghostclaw.sh` | ghostclaw/scripts/ |
| `infra/Caddyfile.*` | ghostclaw/infra/ |
| `docker-compose.vps.yml` | ghostclaw/ |

---

## Migration Commands

```bash
# 1. Create lippyclaw branch
git checkout -b lippyclaw-rebrand

# 2. Update package.json
# (edit as shown above)

# 3. Create new platform integration files
# (create src/lib/slack.ts, discord.ts, whatsapp.ts)

# 4. Update README
# (complete rewrite)

# 5. Test native installation
npm install
npm run dev

# 6. Commit changes
git add .
git commit -m "Rebrand to lippyclaw standalone product"

# 7. Push and create PR
git push origin lippyclaw-rebrand
```

---

## Post-Migration

After the lippyclaw rebrand is complete:

1. **Publish lippyclaw to npm** (optional):
   ```bash
   npm publish
   ```

2. **Create ghostclaw wrapper repo**:
   - Initialize new repository
   - Add lippyclaw as dependency
   - Test deployment flow

3. **Update documentation links**:
   - Point all docs to lippyclaw repo
   - ghostclaw docs reference lippyclaw as the wrapped service
