# IronClaw WASM Tools

This directory contains WebAssembly tools that extend IronClaw's capabilities while maintaining strict security through capability-based isolation.

## Tool Structure

Each tool follows this structure:

```
tools/<tool_name>/
├── Cargo.toml          # Rust package manifest
├── Manifest.toml       # Security capabilities manifest
├── src/
│   └── lib.rs          # Tool implementation
└── target/
    └── wasm32-wasi/
        └── release/
            └── <tool_name>.wasm  # Compiled WASM binary
```

## Security Model

Tools are sandboxed with:

1. **Filesystem Scopes**: Explicit read-only (`fs_ro_scopes`) and read-write (`fs_rw_scopes`) paths
2. **Network Allowlists**: Only specified hosts and ports are accessible
3. **Process Isolation**: No shell execution, spawning, or forking
4. **Resource Limits**: Memory, CPU time, and wall time constraints
5. **Audit Logging**: All invocations are logged for security review

## Available Tools

### chutes_stt

Speech-to-text transcription using Chutes.ai Whisper models.

**Capabilities**:
- Network: `llm.chutes.ai:443` only
- FS Read: `/tmp/stt_input/`, `/agents/mentor/`
- FS Write: `/tmp/stt_output/`, `/tmp/stt_cache/`
- Max Memory: 256MB
- Max Execution: 30s

**Usage**:
```rust
let result = chutes_stt::transcribe(TranscribeInput {
    audio_path: "/tmp/stt_input/voice.ogg".into(),
    mime_type: "audio/ogg".into(),
    language: Some("en".into()),
})?;
println!("Transcription: {}", result.transcription);
```

### chutes_tts

Text-to-speech with voice cloning using Chutes.ai CSM/Kokoro models.

**Capabilities**:
- Network: `llm.chutes.ai:443` only
- FS Read: `/agents/mentor/` (master voice sample - PROTECTED)
- FS Write: `/tmp/tts_output/`, `/tmp/tts_cache/`, `/agents/mentor/checkpoints/`
- Max Memory: 512MB
- Max Execution: 45s

**Protected Files**:
- `/agents/mentor/master-voice.wav` - Read-only, checksum verified, cannot be modified or deleted

**Usage**:
```rust
let result = chutes_tts::synthesize(SynthesizeInput {
    text: "Hello, this is the mentor voice.".into(),
    reference_audio_path: "/agents/mentor/master-voice.wav".into(),
    model: "sesame/csm-1b".into(),
    format: "mp3".into(),
})?;
println!("Audio generated: {}", result.audio_path);
```

## Building Tools

```bash
# Add WASM target
rustup target add wasm32-wasi

# Build all tools
cargo build --release --target wasm32-wasi -p chutes_stt
cargo build --release --target wasm32-wasi -p chutes_tts

# Output location
ls target/wasm32-wasi/release/*.wasm
```

## Manifest.toml Reference

| Section | Key | Description |
|---------|-----|-------------|
| `[tool]` | `name` | Tool identifier |
| | `version` | Semantic version |
| | `description` | Human-readable description |
| `[entrypoint]` | `wasm_file` | Path to compiled WASM |
| | `function` | Exported function to call |
| `[capabilities]` | `network` | Network access config |
| | `filesystem` | FS scopes and denials |
| | `process` | Process execution config |
| | `environment` | Allowed env vars |
| `[resources]` | `max_memory_mb` | Memory limit |
| | `max_cpu_time_ms` | CPU time limit |
| | `max_wall_time_ms` | Wall clock limit |
| `[input]` | `<param>` | Input schema definition |
| `[output]` | `<field>` | Output schema definition |
| `[audit]` | `log_*` | Audit logging config |

## Security Best Practices

1. **Least Privilege**: Grant minimum required capabilities
2. **Explicit Denials**: Use `fs_denied` to block sensitive paths
3. **Protected Files**: Mark critical files as immutable
4. **Checksum Verification**: Verify integrity of trusted files
5. **Audit Everything**: Log all access attempts
6. **Fail Closed**: Deny by default, allow explicitly

## Adding New Tools

1. Create `tools/<tool_name>/` directory
2. Add `Cargo.toml` with `crate-type = ["cdylib"]`
3. Write `Manifest.toml` with security capabilities
4. Implement tool logic in `src/lib.rs`
5. Add to workspace `Cargo.toml` members
6. Register in `src/config/settings.toml`

See existing tools for reference implementations.
