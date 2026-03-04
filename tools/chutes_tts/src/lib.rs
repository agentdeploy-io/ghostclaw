//! Chutes Text-to-Speech WASM Tool with Voice Cloning Support
//!
//! This module provides text-to-speech synthesis using Chutes.ai CSM-1B and Kokoro models
//! with voice cloning capabilities. It reads reference audio from protected paths and
//! synthesizes speech that matches the voice characteristics.

use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use serde::{Deserialize, Serialize};
use wasm_bindgen::prelude::*;
use web_sys::console;

/// Error types for TTS operations
#[derive(Debug, thiserror::Error)]
pub enum TtsError {
    #[error("Invalid input: {0}")]
    InvalidInput(String),
    #[error("File system error: {0}")]
    FileSystem(String),
    #[error("Network error: {0}")]
    Network(String),
    #[error("API error: {0}")]
    ApiError(String),
    #[error("Audio processing error: {0}")]
    AudioProcessing(String),
    #[error("Voice cloning error: {0}")]
    VoiceCloning(String),
}

/// Input parameters for TTS synthesis
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TtsInput {
    /// Text to synthesize into speech
    pub text: String,
    /// Path to voice sample for cloning (must be in fs_ro_scopes)
    #[serde(default = "default_voice_path")]
    pub reference_audio_path: String,
    /// TTS model to use
    #[serde(default = "default_model")]
    pub model: String,
    /// Output audio format
    #[serde(default = "default_format")]
    pub format: String,
    /// Speech speed multiplier (0.5-2.0)
    #[serde(default = "default_speed")]
    pub speed: f64,
    /// Output path for synthesized audio (must be in fs_rw_scopes)
    #[serde(default = "default_output_path")]
    pub output_path: String,
}

fn default_voice_path() -> String {
    "/agents/mentor/master-voice.wav".to_string()
}

fn default_model() -> String {
    "sesame/csm-1b".to_string()
}

fn default_format() -> String {
    "mp3".to_string()
}

fn default_speed() -> f64 {
    1.0
}

fn default_output_path() -> String {
    "/tmp/tts_output/synthesis.wav".to_string()
}

/// Output result from TTS synthesis
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TtsOutput {
    /// Path to synthesized audio file
    pub audio_path: String,
    /// Audio duration in milliseconds
    pub duration_ms: f64,
    /// Model that was used (may differ from requested if fallback)
    pub model_used: String,
    /// Number of characters in input text
    pub character_count: usize,
}

/// API request payload for Chutes.ai
#[derive(Debug, Serialize)]
struct ChutesApiRequest {
    model: String,
    input: ApiInput,
    parameters: ApiParameters,
}

#[derive(Debug, Serialize)]
struct ApiInput {
    text: String,
    reference_audio: Option<String>,
    reference_audio_format: Option<String>,
}

#[derive(Debug, Serialize)]
struct ApiParameters {
    response_format: String,
    speed: f64,
}

/// API response from Chutes.ai
#[derive(Debug, Deserialize)]
struct ChutesApiResponse {
    data: Option<ApiData>,
    error: Option<ApiError>,
}

#[derive(Debug, Deserialize)]
struct ApiData {
    audio: Option<String>,
    duration: Option<f64>,
}

#[derive(Debug, Deserialize)]
struct ApiError {
    message: String,
}

/// Validate that a path is within allowed scopes
fn validate_path_scope(path: &str, allowed_scopes: &[&str]) -> Result<(), TtsError> {
    for scope in allowed_scopes {
        if path.starts_with(scope) {
            return Ok(());
        }
    }
    Err(TtsError::InvalidInput(format!(
        "Path '{}' is not within allowed scopes: {:?}",
        path, allowed_scopes
    )))
}

/// Validate input parameters
fn validate_input(input: &TtsInput) -> Result<(), TtsError> {
    // Validate text
    if input.text.is_empty() {
        return Err(TtsError::InvalidInput("Text cannot be empty".to_string()));
    }
    if input.text.len() > 2000 {
        return Err(TtsError::InvalidInput(
            "Text exceeds maximum length of 2000 characters".to_string(),
        ));
    }

    // Validate speed
    if input.speed < 0.5 || input.speed > 2.0 {
        return Err(TtsError::InvalidInput(
            "Speed must be between 0.5 and 2.0".to_string(),
        ));
    }

    // Validate reference audio path (read-only scopes)
    let ro_scopes: &[&str] = &["/agents/mentor/", "/tmp/tts_input/"];
    validate_path_scope(&input.reference_audio_path, ro_scopes)?;

    // Validate output path (read-write scopes)
    let rw_scopes: &[&str] = &["/tmp/tts_output/", "/tmp/tts_cache/", "/agents/mentor/checkpoints/"];
    validate_path_scope(&input.output_path, rw_scopes)?;

    Ok(())
}

/// Read audio file and convert to base64
/// This uses the WASM host's file system interface
async fn read_audio_file(path: &str) -> Result<String, TtsError> {
    // In WASM environment, we use the host-provided file system
    // This is a placeholder that would be implemented by the host runtime
    log_info(&format!("Reading audio file from: {}", path));

    // The actual file reading is done by the host runtime
    // We simulate the interface here
    let read_result = read_file_from_host(path).await?;

    // Convert to base64
    let base64_audio = BASE64.encode(&read_result);
    log_info(&format!(
        "Audio file encoded to base64 ({} bytes)",
        base64_audio.len()
    ));

    Ok(base64_audio)
}

/// Host file system read operation
/// This function is called by the WASM module but implemented by the host
async fn read_file_from_host(path: &str) -> Result<Vec<u8>, TtsError> {
    // This is a stub - the actual implementation depends on the host runtime
    // In a real WASM environment, this would call into the host's FS API
    Err(TtsError::FileSystem(format!(
        "Host runtime must implement file read for: {}",
        path
    )))
}

/// Write audio data to output path
async fn write_audio_file(path: &str, data: &[u8]) -> Result<(), TtsError> {
    log_info(&format!("Writing audio file to: {}", path));

    // The actual file writing is done by the host runtime
    write_file_to_host(path, data).await?;

    Ok(())
}

/// Host file system write operation
async fn write_file_to_host(_path: &str, _data: &[u8]) -> Result<(), TtsError> {
    // This is a stub - the actual implementation depends on the host runtime
    Err(TtsError::FileSystem(
        "Host runtime must implement file write".to_string(),
    ))
}

/// Call Chutes.ai API for TTS synthesis
async fn call_chutes_api(
    text: &str,
    reference_audio_base64: Option<&str>,
    model: &str,
    format: &str,
    speed: f64,
) -> Result<(Vec<u8>, f64), TtsError> {
    let api_key = get_api_key_from_env()?;
    let base_url = get_base_url_from_env().unwrap_or_else(|| "https://llm.chutes.ai".to_string());

    log_info(&format!("Calling Chutes.ai API at: {}", base_url));
    log_info(&format!("Using model: {}", model));

    // Build request payload
    let request_payload = ChutesApiRequest {
        model: model.to_string(),
        input: ApiInput {
            text: text.to_string(),
            reference_audio: reference_audio_base64.map(String::from),
            reference_audio_format: if reference_audio_base64.is_some() {
                Some("wav".to_string())
            } else {
                None
            },
        },
        parameters: ApiParameters {
            response_format: format.to_string(),
            speed,
        },
    };

    // Serialize request
    let request_body = serde_json::to_string(&request_payload).map_err(|e| {
        TtsError::ApiError(format!("Failed to serialize request: {}", e))
    })?;

    // Make HTTP request using wasm-bindgen-futures
    let response = make_http_request(
        &format!("{}/v1/run", base_url),
        &api_key,
        &request_body,
    )
    .await?;

    // Parse response
    let api_response: ChutesApiResponse = serde_json::from_str(&response).map_err(|e| {
        TtsError::ApiError(format!("Failed to parse API response: {}", e))
    })?;

    // Check for API errors
    if let Some(error) = api_response.error {
        return Err(TtsError::ApiError(error.message));
    }

    // Extract audio data
    let data = api_response
        .data
        .ok_or_else(|| TtsError::ApiError("No data in API response".to_string()))?;

    let audio_base64 = data
        .audio
        .ok_or_else(|| TtsError::ApiError("No audio in API response".to_string()))?;

    let duration = data.duration.unwrap_or(0.0);

    // Decode base64 audio
    let audio_data = BASE64
        .decode(&audio_base64)
        .map_err(|e| TtsError::AudioProcessing(format!("Failed to decode audio: {}", e)))?;

    log_info(&format!(
        "Received {} bytes of audio data, duration: {}ms",
        audio_data.len(),
        duration
    ));

    Ok((audio_data, duration))
}

/// Get API key from environment
fn get_api_key_from_env() -> Result<String, TtsError> {
    // In WASM, we get environment variables from the host
    get_env_var("CHUTES_API_KEY").ok_or_else(|| {
        TtsError::InvalidInput("CHUTES_API_KEY environment variable not set".to_string())
    })
}

/// Get base URL from environment
fn get_base_url_from_env() -> Option<String> {
    get_env_var("CHUTES_BASE_URL")
}

/// Get environment variable (host-provided)
fn get_env_var(name: &str) -> Option<String> {
    // This is a stub - the actual implementation depends on the host runtime
    // In a real WASM environment, this would call into the host's env API
    log_info(&format!("Requesting env var: {}", name));
    None
}

/// Make HTTP POST request to Chutes.ai
async fn make_http_request(
    _url: &str,
    _api_key: &str,
    _body: &str,
) -> Result<String, TtsError> {
    // This uses wasm-bindgen-futures to make async HTTP requests
    // The actual implementation depends on the host runtime providing fetch API
    Err(TtsError::Network(
        "Host runtime must implement HTTP fetch".to_string(),
    ))
}

/// Log info message to console
fn log_info(message: &str) {
    console::log_1(&JsValue::from_str(&format!("[chutes_tts] {}", message)));
}

/// Log error message to console
fn log_error(message: &str) {
    console::error_1(&JsValue::from_str(&format!("[chutes_tts] ERROR: {}", message)));
}

/// Main TTS synthesis function with voice cloning
///
/// This is the primary entry point for the WASM module.
/// It reads the reference audio, calls the Chutes.ai API,
/// and saves the synthesized audio to the output path.
#[wasm_bindgen]
pub async fn synthesize(input_json: &str) -> Result<JsValue, JsValue> {
    log_info("Starting TTS synthesis...");

    // Parse input
    let input: TtsInput = serde_json::from_str(input_json).map_err(|e| {
        let err = TtsError::InvalidInput(format!("Failed to parse input JSON: {}", e));
        log_error(&err.to_string());
        JsValue::from_str(&err.to_string())
    })?;

    // Validate input
    validate_input(&input).map_err(|e| {
        log_error(&e.to_string());
        JsValue::from_str(&e.to_string())
    })?;

    log_info(&format!(
        "Synthesizing {} characters using model: {}",
        input.text.len(),
        input.model
    ));

    // Read reference audio file
    log_info(&format!(
        "Reading reference audio from: {}",
        input.reference_audio_path
    ));

    let reference_audio_base64 = read_audio_file(&input.reference_audio_path)
        .await
        .map_err(|e| {
            log_error(&e.to_string());
            JsValue::from_str(&e.to_string())
        })?;

    // Call Chutes.ai API
    let (audio_data, duration) = call_chutes_api(
        &input.text,
        Some(&reference_audio_base64),
        &input.model,
        &input.format,
        input.speed,
    )
    .await
    .map_err(|e| {
        log_error(&e.to_string());
        JsValue::from_str(&e.to_string())
    })?;

    // Write output audio file
    write_audio_file(&input.output_path, &audio_data)
        .await
        .map_err(|e| {
            log_error(&e.to_string());
            JsValue::from_str(&e.to_string())
        })?;

    // Build output
    let output = TtsOutput {
        audio_path: input.output_path.clone(),
        duration_ms: duration,
        model_used: input.model.clone(),
        character_count: input.text.len(),
    };

    log_info(&format!(
        "Synthesis complete. Output: {} ({}ms)",
        output.audio_path, output.duration_ms
    ));

    // Serialize output to JS value
    let output_json = serde_json::to_string(&output).map_err(|e| {
        let err = TtsError::ApiError(format!("Failed to serialize output: {}", e));
        log_error(&err.to_string());
        JsValue::from_str(&err.to_string())
    })?;

    Ok(JsValue::from_str(&output_json))
}

/// Synthesize without voice cloning (fallback mode)
#[wasm_bindgen]
pub async fn synthesize_fallback(input_json: &str) -> Result<JsValue, JsValue> {
    log_info("Starting TTS synthesis (fallback mode, no voice cloning)...");

    // Parse input
    let mut input: TtsInput = serde_json::from_str(input_json).map_err(|e| {
        let err = TtsError::InvalidInput(format!("Failed to parse input JSON: {}", e));
        log_error(&err.to_string());
        JsValue::from_str(&err.to_string())
    })?;

    // Use Kokoro fallback model
    input.model = "hexgrad/Kokoro-82M".to_string();

    // Validate input
    validate_input(&input).map_err(|e| {
        log_error(&e.to_string());
        JsValue::from_str(&e.to_string())
    })?;

    log_info(&format!(
        "Synthesizing {} characters using fallback model: {}",
        input.text.len(),
        input.model
    ));

    // Call Chutes.ai API without reference audio
    let (audio_data, duration) = call_chutes_api(
        &input.text,
        None, // No reference audio for fallback
        &input.model,
        &input.format,
        input.speed,
    )
    .await
    .map_err(|e| {
        log_error(&e.to_string());
        JsValue::from_str(&e.to_string())
    })?;

    // Write output audio file
    write_audio_file(&input.output_path, &audio_data)
        .await
        .map_err(|e| {
            log_error(&e.to_string());
            JsValue::from_str(&e.to_string())
        })?;

    // Build output
    let output = TtsOutput {
        audio_path: input.output_path.clone(),
        duration_ms: duration,
        model_used: input.model.clone(),
        character_count: input.text.len(),
    };

    log_info(&format!(
        "Fallback synthesis complete. Output: {} ({}ms)",
        output.audio_path, output.duration_ms
    ));

    // Serialize output to JS value
    let output_json = serde_json::to_string(&output).map_err(|e| {
        let err = TtsError::ApiError(format!("Failed to serialize output: {}", e));
        log_error(&err.to_string());
        JsValue::from_str(&err.to_string())
    })?;

    Ok(JsValue::from_str(&output_json))
}

/// Get the default voice path
#[wasm_bindgen]
pub fn get_default_voice_path() -> String {
    default_voice_path()
}

/// Get the default model
#[wasm_bindgen]
pub fn get_default_model() -> String {
    default_model()
}

/// Validate a path is within allowed scopes
#[wasm_bindgen]
pub fn validate_path(path: &str, path_type: &str) -> Result<bool, JsValue> {
    match path_type {
        "ro" => {
            let ro_scopes: &[&str] = &["/agents/mentor/", "/tmp/tts_input/"];
            Ok(validate_path_scope(path, ro_scopes).is_ok())
        }
        "rw" => {
            let rw_scopes: &[&str] =
                &["/tmp/tts_output/", "/tmp/tts_cache/", "/agents/mentor/checkpoints/"];
            Ok(validate_path_scope(path, rw_scopes).is_ok())
        }
        _ => Err(JsValue::from_str("Invalid path_type, must be 'ro' or 'rw'")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_values() {
        assert_eq!(default_voice_path(), "/agents/mentor/master-voice.wav");
        assert_eq!(default_model(), "sesame/csm-1b");
        assert_eq!(default_format(), "mp3");
        assert!((default_speed() - 1.0).abs() < f64::EPSILON);
    }

    #[test]
    fn test_validate_path_scope() {
        let ro_scopes: &[&str] = &["/agents/mentor/", "/tmp/tts_input/"];

        assert!(validate_path_scope("/agents/mentor/master-voice.wav", ro_scopes).is_ok());
        assert!(validate_path_scope("/tmp/tts_input/audio.wav", ro_scopes).is_ok());
        assert!(validate_path_scope("/etc/passwd", ro_scopes).is_err());
        assert!(validate_path_scope("/workspace/file.wav", ro_scopes).is_err());
    }

    #[test]
    fn test_validate_input() {
        let valid_input = TtsInput {
            text: "Hello, world!".to_string(),
            reference_audio_path: "/agents/mentor/master-voice.wav".to_string(),
            model: "sesame/csm-1b".to_string(),
            format: "mp3".to_string(),
            speed: 1.0,
            output_path: "/tmp/tts_output/output.mp3".to_string(),
        };

        assert!(validate_input(&valid_input).is_ok());

        let empty_text = TtsInput {
            text: "".to_string(),
            ..valid_input.clone()
        };
        assert!(validate_input(&empty_text).is_err());

        let invalid_speed = TtsInput {
            speed: 3.0,
            ..valid_input.clone()
        };
        assert!(validate_input(&invalid_speed).is_err());

        let invalid_ro_path = TtsInput {
            reference_audio_path: "/etc/passwd".to_string(),
            ..valid_input.clone()
        };
        assert!(validate_input(&invalid_ro_path).is_err());

        let invalid_rw_path = TtsInput {
            output_path: "/workspace/output.mp3".to_string(),
            ..valid_input
        };
        assert!(validate_input(&invalid_rw_path).is_err());
    }
}
