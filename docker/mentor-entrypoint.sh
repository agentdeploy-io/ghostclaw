#!/bin/bash
# Mentor Worker Entrypoint Script
# Performs security checks and initializes the Mentor AI

set -euo pipefail

echo "[Mentor Entrypoint] Starting initialization..."

# ============================================================================
# INTEGRITY VERIFICATION
# ============================================================================

echo "[Mentor Entrypoint] Verifying file integrity..."

PERSONA_FILE="/app/agents/mentor/persona.md"
VOICE_FILE="/app/agents/mentor/master-voice.wav"
PERSONA_CHECKSUM_FILE="/app/agents/mentor/checkpoints/persona_checksum.sha256"
VOICE_CHECKSUM_FILE="/app/agents/mentor/checkpoints/voice_checksum.sha256"

# Generate current checksums
CURRENT_PERSONA_CHECKSUM=$(sha256sum "$PERSONA_FILE" | awk '{print $1}')
CURRENT_VOICE_CHECKSUM=$(sha256sum "$VOICE_FILE" | awk '{print $1}')

# Check if stored checksums exist
if [[ -f "$PERSONA_CHECKSUM_FILE" ]]; then
    STORED_PERSONA_CHECKSUM=$(cat "$PERSONA_CHECKSUM_FILE")
    if [[ "$CURRENT_PERSONA_CHECKSUM" != "$STORED_PERSONA_CHECKSUM" ]]; then
        echo "[CRITICAL] Persona checksum mismatch!"
        echo "  Expected: $STORED_PERSONA_CHECKSUM"
        echo "  Got:      $CURRENT_PERSONA_CHECKSUM"
        echo "[Mentor Entrypoint] REFUSING TO START - Security violation detected"
        exit 1
    fi
    echo "[Mentor Entrypoint] Persona checksum verified: OK"
else
    echo "[Mentor Entrypoint] No stored persona checksum, creating initial..."
    echo "$CURRENT_PERSONA_CHECKSUM" > "$PERSONA_CHECKSUM_FILE"
fi

if [[ -f "$VOICE_CHECKSUM_FILE" ]]; then
    STORED_VOICE_CHECKSUM=$(cat "$VOICE_CHECKSUM_FILE")
    if [[ "$CURRENT_VOICE_CHECKSUM" != "$STORED_VOICE_CHECKSUM" ]]; then
        echo "[CRITICAL] Voice sample checksum mismatch!"
        echo "  Expected: $STORED_VOICE_CHECKSUM"
        echo "  Got:      $CURRENT_VOICE_CHECKSUM"
        echo "[Mentor Entrypoint] REFUSING TO START - Security violation detected"
        exit 1
    fi
    echo "[Mentor Entrypoint] Voice sample checksum verified: OK"
else
    echo "[Mentor Entrypoint] No stored voice checksum, creating initial..."
    echo "$CURRENT_VOICE_CHECKSUM" > "$VOICE_CHECKSUM_FILE"
fi

# ============================================================================
# PERMISSION VERIFICATION
# ============================================================================

echo "[Mentor Entrypoint] Verifying file permissions..."

# Check persona.md is read-only
PERSONA_PERMS=$(stat -c %a "$PERSONA_FILE")
if [[ "$PERSONA_PERMS" != "444" ]]; then
    echo "[WARNING] persona.md should be read-only (444), got: $PERSONA_PERMS"
    chmod 444 "$PERSONA_FILE" 2>/dev/null || echo "[WARNING] Could not fix permissions"
fi

# Check master-voice.wav is read-only
VOICE_PERMS=$(stat -c %a "$VOICE_FILE")
if [[ "$VOICE_PERMS" != "444" ]]; then
    echo "[WARNING] master-voice.wav should be read-only (444), got: $VOICE_PERMS"
    chmod 444 "$VOICE_FILE" 2>/dev/null || echo "[WARNING] Could not fix permissions"
fi

# ============================================================================
# DIRECTORY SETUP
# ============================================================================

echo "[Mentor Entrypoint] Setting up directories..."

# Ensure temp directories exist and are writable
for dir in /app/tmp/stt_input /app/tmp/stt_output /app/tmp/stt_cache \
           /app/tmp/tts_input /app/tmp/tts_output /app/tmp/tts_cache \
           /app/agents/mentor/checkpoints; do
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
    fi
    if [[ ! -w "$dir" ]]; then
        echo "[ERROR] Directory not writable: $dir"
        exit 1
    fi
done

# ============================================================================
# ENVIRONMENT VERIFICATION
# ============================================================================

echo "[Mentor Entrypoint] Verifying environment..."

# Required environment variables
REQUIRED_VARS=(
    "CHUTES_API_KEY"
    "MENTOR_WORKSPACE"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo "[WARNING] Required environment variable not set: $var"
    fi
done

# Optional but recommended
if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
    echo "[INFO] Telegram integration disabled (TELEGRAM_BOT_TOKEN not set)"
fi

# ============================================================================
# LOGGING
# ============================================================================

echo "[Mentor Entrypoint] Initializing audit log..."

AUDIT_LOG="/app/agents/mentor/entrypoint.log"
{
    echo "=== Mentor Entrypoint Log ==="
    echo "Timestamp: $(date -Iseconds)"
    echo "Persona Checksum: $CURRENT_PERSONA_CHECKSUM"
    echo "Voice Checksum: $CURRENT_VOICE_CHECKSUM"
    echo "User: $(whoami)"
    echo "UID: $(id -u)"
    echo "GID: $(id -g)"
    echo "=== End Header ==="
} >> "$AUDIT_LOG"

# ============================================================================
# START MENTOR
# ============================================================================

echo "[Mentor Entrypoint] All checks passed. Starting Mentor Worker..."

exec "$@"
