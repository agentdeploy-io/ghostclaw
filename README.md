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

## Architecture

Services in the stack:
- `lippyclaw` - Main API and orchestration
- `worker` - Background job processor
- `mentor-mcp` - MCP adapter for mentor persona chat + voice tools
- `camoufox-mcp` - MCP adapter for browser automation
- `redis` - Queue and state management
- `postgres` (optional) - For Ironclaw runtime with memory

## Command Reference

```bash
# Development
npm run dev              # Start main API with hot reload
npm run dev:worker       # Start worker with hot reload

# Production
npm run build            # Compile TypeScript
npm start                # Start main API
npm run start:worker     # Start worker
npm run start:mentor-mcp # Start mentor MCP server
npm run start:camoufox-mcp # Start camoufox MCP server

# Utilities
npm run typecheck        # Type check without emitting
```

## Configuration

### Required Variables

| Variable | Description |
|----------|-------------|
| `MAIN_LLM_API_KEY` | API key for main LLM (ChutesAI) |
| `SUB_LLM_API_KEY` | API key for sub-agent LLM |
| `REDIS_URL` | Redis connection URL |

### Platform Integrations

#### Telegram

```bash
ENABLE_TELEGRAM=true
TELEGRAM_BOT_TOKEN=your_bot_token
TELEGRAM_WEBHOOK_SECRET=your_secret
```

#### Slack

```bash
ENABLE_SLACK=true
SLACK_BOT_TOKEN=xoxb-...
SLACK_SIGNING_SECRET=...
SLACK_APP_TOKEN=xapp-...
```

#### Discord

```bash
ENABLE_DISCORD=true
DISCORD_BOT_TOKEN=...
DISCORD_CLIENT_ID=...
```

#### WhatsApp

```bash
ENABLE_WHATSAPP=true
WHATSAPP_PHONE_NUMBER_ID=...
WHATSAPP_ACCESS_TOKEN=...
WHATSAPP_VERIFY_TOKEN=...
```

### Mentor Configuration

```bash
MENTOR_NAME=Lippyclaw Mentor
MENTOR_LLM_API_KEY=...
ENABLE_MENTOR_VOICE=true
MENTOR_VOICE_API_KEY=...
MENTOR_VOICE_SAMPLE_PATH=./mentor/master-voice.wav
```

## Mentor Tools (Auto-Wired)

Mentor tools exposed to the platform:
- `mentor.chat` - Chat with mentor persona
- `mentor.speak` - Convert text to mentor voice
- `mentor.transcribe` - Transcribe audio to text
- `mentor.voice_bootstrap` - Generate voice context
- `mentor.status` - Check mentor runtime status

Voice processing flow (Chutes):
1. Place reference media at `./mentor/master-voice.wav`
2. Set `MENTOR_VOICE_API_KEY` in `.env`
3. Voice context is auto-generated on first run
4. Runtime pipeline:
   - STT: `MENTOR_CHUTES_WHISPER_MODEL`
   - Voice clone: `MENTOR_CHUTES_CSM_MODEL`
   - Fallback TTS: `MENTOR_CHUTES_KOKORO_MODEL`

## Camoufox Tools (Auto-Wired)

Browser automation tools with prefix `camoufox_`:
- `camoufox_browser.session_new`
- `camoufox_browser.goto`
- `camoufox_browser.click`
- `camoufox_browser.fill`
- `camoufox_browser.press`
- `camoufox_browser.click_xy`
- `camoufox_browser.wait_for_selector`
- `camoufox_browser.wait`
- `camoufox_browser.screenshot`
- `camoufox_browser.session_close`

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/healthz` | GET | Health check |
| `/` | GET | API info |
| `/api/v1/jobs` | POST | Queue browser job |
| `/api/v1/jobs/:jobId` | GET | Get job status |
| `/telegram/webhook` | POST | Telegram webhook |
| `/slack/webhook` | POST | Slack webhook |
| `/discord/webhook` | POST | Discord webhook |
| `/whatsapp/webhook` | POST | WhatsApp webhook |

## Resource Requirements

### Local Development
- 4 vCPU
- 8 GB RAM
- 30 GB free disk

### Production
- 8 vCPU
- 16 GB RAM
- 60 GB free disk

## Troubleshooting

### Redis Connection Failed

Ensure Redis is running:
```bash
redis-cli ping  # Should return PONG
```

### Mentor Voice Bootstrap Fails

Check:
- `MENTOR_VOICE_API_KEY` is set
- Sample file exists at `./mentor/master-voice.wav`
- Chutes endpoint is valid

### Webhook Setup Fails

Check:
- Platform tokens are configured
- Webhook secret matches
- Tunnel is running (local mode)

## Security Notes

- Store secrets in `.env` (mode `600`)
- Never commit `.env`
- Rotate API tokens after tests
- Use `INTERNAL_API_TOKEN` for internal API routes

## License

MIT
