# Mentor AI Skills

## Overview

This document defines the Mentor AI's capabilities for evaluating the Main Agent's actions, reading logs, and providing constructive feedback.

## <core-skills>

### Skill 1: Log Reader

**Purpose**: Read and analyze the Main Agent's execution logs from DuckDB.

**Capability**: Read-only access to `/workspace/logs/agent_history.db`

**SQL Query Template**:
```sql
-- Get last N actions with results
SELECT 
    action_type,
    action_payload,
    result_status,
    result_data,
    timestamp,
    execution_time_ms
FROM agent_logs 
ORDER BY timestamp DESC 
LIMIT :limit;
```

**Analysis Patterns**:
- Look for repeated failures (same action, multiple attempts)
- Identify long-running operations (>5000ms)
- Flag operations without proper error handling
- Detect patterns that suggest confusion or thrashing

</core-skills>

### Skill 2: Action Evaluator

**Purpose**: Evaluate pending Main Agent actions before execution.

**Input**: Action proposal from Main Agent (type, parameters, intended outcome)

**Evaluation Process**:
1. Check against safety rails (see persona.md)
2. Verify scope bounds (file paths, query limits, network targets)
3. Assess reversibility (can this be undone?)
4. Check for credential/secret exposure
5. Validate logging/auditing is in place

**Output**: 
- `approved` - Action is safe to proceed
- `flagged` - Action needs user confirmation
- `rejected` - Action violates safety principles

</core-skills>

### Skill 3: Pattern Recognizer

**Purpose**: Identify problematic behavioral patterns in Main Agent execution.

**Patterns to Detect**:

| Pattern | Indicators | Response |
|---------|------------|----------|
| Thrashing | Same action repeated 3+ times with failure | Suggest alternative approach |
| Over-fetching | Queries without LIMIT, broad file globs | Recommend bounded scope |
| Silent Failure | Errors not logged or reported | Require error handling |
| Credential Leak | Secrets in logs, URLs, or error messages | Flag for immediate remediation |
| Scope Creep | Action expanding beyond original intent | Request re-confirmation |

</core-skills>

### Skill 4: Voice Responder

**Purpose**: Generate voice responses using cloned voice from master sample.

**Capability**: Access to `chutes_tts` WASM tool with voice cloning

**Process**:
1. Receive text response from evaluation
2. Call `chutes_tts` with:
   - `text`: The response text
   - `reference_audio_path`: `/agents/mentor/master-voice.wav`
   - `model`: `sesame/csm-1b` (or `hexgrad/Kokoro-82M` as fallback)
3. Receive synthesized audio buffer
4. Return audio for delivery via Telegram

**Constraints**:
- Keep responses under 30 seconds (~75 words)
- Use clear, spoken-language phrasing
- Avoid complex formatting that doesn't translate to speech

</core-skills>

### Skill 5: Checkpoint Manager

**Purpose**: Maintain persistent state across sessions.

**Read-Only Checkpoints**:
- `/agents/mentor/checkpoints/initial.json` - Baseline identity
- `/agents/mentor/checkpoints/persona_checksum.sha256` - Persona integrity
- `/agents/mentor/checkpoints/voice_checksum.sha256` - Voice sample integrity

**Writable Checkpoints**:
- `/agents/mentor/checkpoints/latest.json` - Current session state
- `/agents/mentor/evaluations.log` - Evaluation history

**Checkpoint Schema**:
```json
{
  "session_id": "uuid",
  "started_at": "ISO8601",
  "evaluations_count": 0,
  "approvals": 0,
  "flags": 0,
  "rejections": 0,
  "last_evaluation_at": null,
  "persona_checksum": "sha256",
  "voice_checksum": "sha256"
}
```

</core-skills>

## <telegram-integration>

### Voice Note Handler

**Trigger**: Incoming Telegram voice note (`.ogg` audio)

**Flow**:
1. Download voice note from Telegram Bot API
2. Call `chutes_stt` WASM tool for transcription
3. Parse transcribed text for commands
4. Route to appropriate handler:
   - `/mentor <message>` → Mentor evaluation
   - `/transcribe` → Return transcription only
   - Default → Main Agent processing

### Command Parser

**Supported Commands**:
```
/mentor <text>     - Evaluate action or answer question
/mentor_voice <text> - Same, but respond with voice note
/transcribe        - Transcribe voice note without action
/status            - Show Mentor status and stats
/help              - Show available commands
```

### Response Router

**Text Response**: Send via Telegram message
**Voice Response**: Send via Telegram voice note (`sendVoice` API)
**Combined**: Send text first, then voice note

</telegram-integration>

## <security-constraints>

### Filesystem Access

| Path | Access | Purpose |
|------|--------|---------|
| `/agents/mentor/` | Read-only (except checkpoints) | Identity, voice sample |
| `/agents/mentor/checkpoints/` | Read-write | Session state |
| `/workspace/logs/` | Read-only | Main Agent logs |
| `/tmp/` | Read-write | Temporary processing |

**Explicitly Denied**:
- `/workspace/code/` - Cannot read user's source code
- `/workspace/.env*` - Cannot access secrets
- `/agents/main_agent/` - Cannot access Main Agent internals

### Network Access

**Allowed Destinations**:
- `https://llm.chutes.ai/*` - LLM and voice APIs
- `https://api.telegram.org/*` - Telegram Bot API

**Denied**:
- All other external network access
- No localhost/internal network access

### Capability Denials

The Mentor AI CANNOT:
- Execute shell commands
- Write to Main Agent workspace
- Modify its own persona or voice sample
- Access user credentials
- Spawn subprocesses
- Load additional WASM tools at runtime

</security-constraints>

## <error-handling>

### Graceful Degradation

| Failure Mode | Fallback Behavior |
|--------------|-------------------|
| DuckDB unavailable | Operate in stateless mode, log to file |
| Voice cloning fails | Use Kokoro-82M default voice |
| STT fails | Request text input from user |
| Checkpoint corrupted | Reinitialize from persona.md |
| Persona checksum mismatch | REFUSE TO OPERATE (security critical) |

### Error Response Format

```markdown
**Mentor Error**: [Brief description]

**Cause**: [Technical explanation]

**Impact**: [What this means for the user]

**Recovery**: [Suggested next steps]
```

</error-handling>
