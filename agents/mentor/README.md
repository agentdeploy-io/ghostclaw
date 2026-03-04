# Mentor AI Agent Directory

This directory contains the Mentor AI's identity, capabilities, and voice profile.

## Files

| File | Purpose | Mutability |
|------|---------|------------|
| `persona.md` | Core identity, safety rails, tone | **IMMUTABLE** (checksum verified) |
| `skills.md` | Capability definitions and log evaluation | Read-only |
| `master-voice.wav` | Voice sample for Chutes.ai cloning | **IMMUTABLE** (checksum verified) |
| `checkpoints/` | Session state persistence | Read-write |
| `evaluations.log` | Evaluation history | Append-only |

## Security

This directory is protected by IronClaw's capability-based security:

- **Main Agent**: No access (cannot read, write, or modify)
- **Mentor Worker**: Read-only (except checkpoints/)
- **WASM Tools**: Execute-only with explicit path scopes

## Checksums

At startup, the Mentor Worker verifies:

```bash
sha256sum persona.md > checkpoints/persona_checksum.sha256
sha256sum master-voice.wav > checkpoints/voice_checksum.sha256
```

If checksums don't match, the Mentor refuses to operate (security critical).

## Voice Sample Requirements

For optimal voice cloning with Chutes.ai:

- **Format**: WAV, 16-bit, 44.1kHz or 48kHz
- **Duration**: 10-15 seconds
- **Content**: Clean speech without background noise
- **Style**: Natural speaking voice, moderate emotion

Example recording command:
```bash
ffmpeg -f avfoundation -i "1:0" -t 15 -ar 48000 -ac 1 master-voice.wav
```

## Adding to lippyclaw

To integrate the Mentor AI into lippyclaw:

1. Add to `Cargo.toml` workspace members (if embedding)
2. Configure in `settings.toml` with capability scopes
3. Mount volume in Docker Compose
4. Register `/mentor` command in Telegram router

See `plans/voice-mcp-security-implementation.md` for full integration guide.
