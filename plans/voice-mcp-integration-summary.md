# Voice-MCP Integration Summary

## Completed Files

This document summarizes the secure voice-mcp integration files created for lippyclaw/ironclaw.

## Directory Structure Created

```
lippyclaw/
├── agents/mentor/
│   ├── persona.md              # Core identity with XML safety tags
│   ├── skills.md               # Capability definitions and log evaluation
│   ├── README.md               # Directory documentation
│   └── checkpoints/            # Session state (created at runtime)
│
├── tools/
│   ├── README.md               # WASM tools documentation
│   ├── chutes_stt/
│   │   └── Manifest.toml       # STT security capabilities
│   └── chutes_tts/
│       └── Manifest.toml       # TTS security capabilities with voice cloning
│
├── src/config/
│   └── settings.toml           # Global capability-based security config
│
├── docker/
│   ├── Dockerfile.mentor-worker # Secure Mentor Worker container
│   └── mentor-entrypoint.sh    # Integrity verification script
│
└── plans/
    └── voice-mcp-integration-summary.md  # This file
```

## Security Architecture

### 1. Capability-Based Security (settings.toml)

| Agent/Tool | Read Access | Write Access | Network |
|------------|-------------|--------------|---------|
| Main Agent | `/workspace/**`, `/tools/**` | `/workspace/**`, `/tmp/main_agent/**` | Configurable |
| Mentor | `/workspace/logs/**`, `/agents/mentor/` | `/agents/mentor/checkpoints/`, `/tmp/mentor/**` | Chutes.ai, Telegram only |
| chutes_stt | `/tmp/stt_input/`, `/agents/mentor/` | `/tmp/stt_output/`, `/tmp/stt_cache/` | Chutes.ai only |
| chutes_tts | `/agents/mentor/` (protected) | `/tmp/tts_output/`, `/agents/mentor/checkpoints/` | Chutes.ai only |

### 2. Protected Files

- `/agents/mentor/persona.md` - Read-only, checksum verified
- `/agents/mentor/master-voice.wav` - Read-only, checksum verified, cannot be modified
- `/agents/mentor/skills.md` - Read-only

### 3. Integrity Verification

The `mentor-entrypoint.sh` script:
1. Computes SHA256 checksums of persona.md and master-voice.wav
2. Compares against stored checksums in checkpoints/
3. **REFUSES TO START** if checksums don't match (security critical)
4. Creates initial checksums if none exist

### 4. Docker Security Hardening

```yaml
services:
  mentor-worker:
    read_only: true           # Read-only root filesystem
    cap_drop:
      - ALL                   # Drop all capabilities
    security_opt:
      - no-new-privileges:true
    volumes:
      - /app/tmp              # Only writable directory
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 512M
```

## Implementation Status

| Component | Status | Files |
|-----------|--------|-------|
| Directory Structure | ✅ Complete | `agents/mentor/` |
| Persona Definition | ✅ Complete | `persona.md` |
| Skills Definition | ✅ Complete | `skills.md` |
| WASM Tool Manifests | ✅ Complete | `tools/*/Manifest.toml` |
| Security Config | ✅ Complete | `settings.toml` |
| Docker Configuration | ✅ Complete | `Dockerfile.mentor-worker`, `mentor-entrypoint.sh` |
| WASM Tool Implementation | ⏳ Pending | `tools/*/src/lib.rs`, `tools/*/Cargo.toml` |
| Mentor Engine (Rust) | ⏳ Pending | `src/mentor_engine.rs` |
| Telegram Router | ⏳ Pending | `src/router.rs` |
| DuckDB Integration | ⏳ Pending | `src/db.rs` |

## Next Steps

### Phase 1: WASM Tool Implementation (Days 1-7)

1. Create `tools/chutes_stt/Cargo.toml`
2. Implement `tools/chutes_stt/src/lib.rs`
3. Create `tools/chutes_tts/Cargo.toml`
4. Implement `tools/chutes_tts/src/lib.rs`
5. Build and test WASM binaries

### Phase 2: Mentor Worker Core (Days 8-14)

1. Create `src/mentor_engine.rs` - Core mentor logic
2. Create `src/router.rs` - Telegram command routing
3. Create `src/capability.rs` - Capability enforcement
4. Integrate DuckDB for log reading
5. Implement checkpoint management

### Phase 3: Integration Testing (Days 15-21)

1. Docker Compose integration
2. End-to-end voice note flow testing
3. Security penetration testing
4. Performance optimization

### Phase 4: Deployment (Days 22-28)

1. Update docker-compose.yml
2. Add voice-mcp to ghostclaw.sh registration
3. Documentation and runbooks
4. Production rollout

## Key Design Decisions

### 1. Separate MCP Server vs Embedded Worker

**Decision**: Embedded Worker (not separate MCP server)

**Rationale**:
- Tighter security integration with IronClaw's capability model
- Direct DuckDB access for log reading
- No network overhead for agent-to-agent communication
- Consistent audit logging

### 2. Voice Cloning Approach

**Decision**: Chutes.ai CSM-1B with Kokoro fallback

**Rationale**:
- CSM-1B provides high-quality zero-shot voice cloning
- Kokoro-82M as fallback ensures availability
- Both models accessible via Chutes.ai unified API

### 3. Checksum Verification

**Decision**: SHA256 verification at startup, refuse on mismatch

**Rationale**:
- Prevents persona/voice tampering
- Detects accidental corruption
- Security-critical: Mentor cannot operate without verified identity

### 4. Dual-Workspace Design

**Decision**: Separate `/workspace` (Main) and `/agents/mentor` (Mentor)

**Rationale**:
- Clear separation of concerns
- Mentor can audit Main without interference
- Read-only symlink for log access maintains security boundary

## Configuration Reference

### Environment Variables

```bash
# Mentor Worker
MENTOR_WORKSPACE=/agents/mentor
CHUTES_API_KEY=your_api_key

# Telegram (optional)
TELEGRAM_BOT_TOKEN=bot_token
TELEGRAM_WEBHOOK_SECRET=webhook_secret

# Voice Configuration
VOICE_MODEL=sesame/csm-1b
VOICE_FALLBACK_MODEL=hexgrad/Kokoro-82M
VOICE_SAMPLE_PATH=/agents/mentor/master-voice.wav
```

### Telegram Commands

| Command | Description | Voice Response |
|---------|-------------|----------------|
| `/mentor <text>` | Evaluate action or answer question | No |
| `/mentor_voice <text>` | Same, but respond with voice | Yes |
| `/transcribe` | Transcribe voice note | No |
| `/status` | Show Mentor status | No |
| `/help` | Show available commands | No |

## Security Checklist

Before deploying to production:

- [ ] Verify persona.md checksum is stored
- [ ] Verify master-voice.wav checksum is stored
- [ ] Test checksum mismatch detection
- [ ] Verify fs_denied paths are enforced
- [ ] Test network allowlist (only Chutes.ai accessible)
- [ ] Verify non-root user execution
- [ ] Test resource limits (CPU, memory)
- [ ] Audit log retention configured
- [ ] Emergency kill switch tested
