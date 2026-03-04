//! Chutes Speech-to-Text WASM Tool with Whisper Model Support
//!
//! This module provides speech-to-text transcription using Chutes.ai Whisper models.
//! It reads audio files from protected paths and transcribes them to text.
//! It respects capability-based security by only reading from fs_ro_scopes paths
//! and writing to fs_rw_scopes paths.

use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use serde::{Deserialize, Serialize};
use wasm_bindgen::prelude::*;
use web_sys::console;

/// Error types for STT operations
#[derive(Debug, thiserror::Error)]
pub enum SttError {
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
    #[error("Transcription error: {0}")]
    Transcription(String),
}

/// Input parameters for STT transcription
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SttInput {
    /// Path to audio file for transcription (must be in fs_ro_scopes)
    pub audio_path: String,
    /// Output path for transcription text (must be in fs_rw_scopes)
    pub output_path: String,
    /// Audio MIME type
    #[serde(default = "default_mime_type")]
    pub mime_type: String,
    /// Optional language code for transcription (e.g., 'en', 'es')
    #[serde(default)]
    pub language: Option<String>,
    /// STT model to use
    #[serde(default = "default_model")]
    pub model: String,
}

fn default_mime_type() -> String {
    "audio/ogg".to_string()
}

fn default_model() -> String {
    "openai/whisper-large-v3-turbo".to_string()
}

/// Output result from STT transcription
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SttOutput {
    /// Transcribed text
    pub transcription: String,
    /// Confidence score (0.0-1.0)
    pub confidence: f64,
    /// Detected language code
    pub language_detected: String,
    /// Audio duration in milliseconds
    pub duration_ms: f64,
    /// Path to output file
    pub output_path: String,
    /// Model that was used
    pub model_used: String,
}

/// API request payload for Chutes.ai STT
#[derive(Debug, Serialize)]
struct ChutesSttApiRequest {
    model: String,
    input: SttApiInput,
    parameters: Option<SttApiParameters>,
}

#[derive(Debug, Serialize)]
struct SttApiInput {
    audio: String,
    audio_format: String,
}

#[derive(Debug, Serialize)]
struct SttApiParameters {
    #[serde(skip_serializing_if = "Option::is_none")]
    language: Option<String>,
    response_format: String,
}

/// API response from Chutes.ai STT
#[derive(Debug, Deserialize)]
struct ChutesSttApiResponse {
    data: Option<SttApiData>,
    error: Option<ApiError>,
}

#[derive(Debug, Deserialize)]
struct SttApiData {
    text: Option<String>,
    #[serde(default)]
    language: Option<String>,
    #[serde(default)]
    duration: Option<f64>,
    #[serde(default)]
    confidence: Option<f64>,
}

#[derive(Debug, Deserialize)]
struct ApiError {
    message: String,
}

/// Validate that a path is within allowed scopes
fn validate_path_scope(path: &str, allowed_scopes: &[&str]) -> Result<(), SttError> {
    for scope in allowed_scopes {
        if path.starts_with(scope) {
            return Ok(());
        }
    }
    Err(SttError::InvalidInput(format!(
        "Path '{}' is not within allowed scopes: {:?}",
        path, allowed_scopes
    )))
}

/// Validate input parameters
fn validate_input(input: &SttInput) -> Result<(), SttError> {
    // Validate audio path (read-only scopes)
    let ro_scopes: &[&str] = &["/agents/mentor/", "/tmp/stt_input/"];
    validate_path_scope(&input.audio_path, ro_scopes)?;

    // Validate output path (read-write scopes)
    let rw_scopes: &[&str] = &["/tmp/stt_output/", "/tmp/stt_cache/"];
    validate_path_scope(&input.output_path, rw_scopes)?;

    // Validate mime type
    let supported_formats = [
        "audio/ogg",
        "audio/wav",
        "audio/mp3",
        "audio/mp4",
        "audio/webm",
    ];
    if !supported_formats.contains(&input.mime_type.as_str()) {
        return Err(SttError::InvalidInput(format!(
            "Unsupported audio format: {}. Supported formats: {:?}",
            input.mime_type, supported_formats
        )));
    }

    Ok(())
}

/// Read audio file and convert to base64
/// This uses the WASM host's file system interface
async fn read_audio_file(path: &str) -> Result<Vec<u8>, SttError> {
    log_info(&format!("Reading audio file from: {}", path));

    // The actual file reading is done by the host runtime
    let read_result = read_file_from_host(path).await?;

    log_info(&format!(
        "Audio file read successfully ({} bytes)",
        read_result.len()
    ));

    Ok(read_result)
}

/// Host file system read operation
/// This function is called by the WASM module but implemented by the host
async fn read_file_from_host(path: &str) -> Result<Vec<u8>, SttError> {
    // This is a stub - the actual implementation depends on the host runtime
    // In a real WASM environment, this would call into the host's FS API
    Err(SttError::FileSystem(format!(
        "Host runtime must implement file read for: {}",
        path
    )))
}

/// Write transcription text to output path
async fn write_transcription_file(path: &str, data: &str) -> Result<(), SttError> {
    log_info(&format!("Writing transcription to: {}", path));

    // The actual file writing is done by the host runtime
    write_file_to_host(path, data.as_bytes()).await?;

    Ok(())
}

/// Host file system write operation
async fn write_file_to_host(_path: &str, _data: &[u8]) -> Result<(), SttError> {
    // This is a stub - the actual implementation depends on the host runtime
    Err(SttError::FileSystem(
        "Host runtime must implement file write".to_string(),
    ))
}

/// Call Chutes.ai API for STT transcription
async fn call_chutes_stt_api(
    audio_data_base64: &str,
    mime_type: &str,
    model: &str,
    language: Option<&str>,
) -> Result<(String, String, f64, f64), SttError> {
    let api_key = get_api_key_from_env()?;
    let base_url = get_base_url_from_env().unwrap_or_else(|| "https://llm.chutes.ai".to_string());

    log_info(&format!("Calling Chutes.ai STT API at: {}", base_url));
    log_info(&format!("Using model: {}", model));

    // Determine audio format from mime type
    let audio_format = mime_type_to_format(mime_type);

    // Build request payload
    let request_payload = ChutesSttApiRequest {
        model: model.to_string(),
        input: SttApiInput {
            audio: audio_data_base64.to_string(),
            audio_format,
        },
        parameters: Some(SttApiParameters {
            language: language.map(String::from),
            response_format: "json".to_string(),
        }),
    };

    // Serialize request
    let request_body = serde_json::to_string(&request_payload).map_err(|e| {
        SttError::ApiError(format!("Failed to serialize request: {}", e))
    })?;

    // Make HTTP request using wasm-bindgen-futures
    let response = make_http_request(
        &format!("{}/v1/run", base_url),
        &api_key,
        &request_body,
    )
    .await?;

    // Parse response
    let api_response: ChutesSttApiResponse = serde_json::from_str(&response).map_err(|e| {
        SttError::ApiError(format!("Failed to parse API response: {}", e))
    })?;

    // Check for API errors
    if let Some(error) = api_response.error {
        return Err(SttError::ApiError(error.message));
    }

    // Extract transcription data
    let data = api_response
        .data
        .ok_or_else(|| SttError::ApiError("No data in API response".to_string()))?;

    let transcription = data
        .text
        .ok_or_else(|| SttError::ApiError("No transcription in API response".to_string()))?;

    let language_detected = data.language.unwrap_or_else(|| "unknown".to_string());
    let duration = data.duration.unwrap_or(0.0);
    let confidence = data.confidence.unwrap_or(0.0);

    log_info(&format!(
        "Received transcription: {} chars, language: {}, confidence: {}, duration: {}ms",
        transcription.len(),
        language_detected,
        confidence,
        duration
    ));

    Ok((transcription, language_detected, duration, confidence))
}

/// Convert MIME type to format string for API
fn mime_type_to_format(mime_type: &str) -> String {
    match mime_type {
        "audio/ogg" => "ogg".to_string(),
        "audio/wav" => "wav".to_string(),
        "audio/mp3" => "mp3".to_string(),
        "audio/mp4" => "mp4".to_string(),
        "audio/webm" => "webm".to_string(),
        _ => "ogg".to_string(), // Default fallback
    }
}

/// Get API key from environment
fn get_api_key_from_env() -> Result<String, SttError> {
    // In WASM, we get environment variables from the host
    get_env_var("CHUTES_API_KEY").ok_or_else(|| {
        SttError::InvalidInput("CHUTES_API_KEY environment variable not set".to_string())
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
) -> Result<String, SttError> {
    // This uses wasm-bindgen-futures to make async HTTP requests
    // The actual implementation depends on the host runtime providing fetch API
    Err(SttError::Network(
        "Host runtime must implement HTTP fetch".to_string(),
    ))
}

/// Log info message to console
fn log_info(message: &str) {
    console::log_1(&JsValue::from_str(&format!("[chutes_stt] {}", message)));
}

/// Log error message to console
fn log_error(message: &str) {
    console::error_1(&JsValue::from_str(&format!("[chutes_stt] ERROR: {}", message)));
}

/// Main STT transcription function
///
/// This is the primary entry point for the WASM module.
/// It reads the audio file, calls the Chutes.ai API for transcription,
/// and saves the transcription text to the output path.
#[wasm_bindgen]
pub async fn transcribe(input_json: &str) -> Result<JsValue, JsValue> {
    log_info("Starting STT transcription...");

    // Parse input
    let input: SttInput = serde_json::from_str(input_json).map_err(|e| {
        let err = SttError::InvalidInput(format!("Failed to parse input JSON: {}", e));
        log_error(&err.to_string());
        JsValue::from_str(&err.to_string())
    })?;

    // Validate input
    validate_input(&input).map_err(|e| {
        log_error(&e.to_string());
        JsValue::from_str(&e.to_string())
    })?;

    log_info(&format!(
        "Transcribing audio from: {} using model: {}",
        input.audio_path, input.model
    ));

    // Read audio file
    log_info(&format!("Reading audio file from: {}", input.audio_path));

    let audio_data = read_audio_file(&input.audio_path)
        .await
        .map_err(|e| {
            log_error(&e.to_string());
            JsValue::from_str(&e.to_string())
        })?;

    // Convert audio to base64
    let audio_base64 = BASE64.encode(&audio_data);
    log_info(&format!(
        "Audio encoded to base64 ({} bytes)",
        audio_base64.len()
    ));

    // Call Chutes.ai API for transcription
    let (transcription, language_detected, duration, confidence) = call_chutes_stt_api(
        &audio_base64,
        &input.mime_type,
        &input.model,
        input.language.as_deref(),
    )
    .await
    .map_err(|e| {
        log_error(&e.to_string());
        JsValue::from_str(&e.to_string())
    })?;

    // Write transcription to output file
    write_transcription_file(&input.output_path, &transcription)
        .await
        .map_err(|e| {
            log_error(&e.to_string());
            JsValue::from_str(&e.to_string())
        })?;

    // Build output
    let output = SttOutput {
        transcription: transcription.clone(),
        confidence,
        language_detected,
        duration_ms: duration,
        output_path: input.output_path.clone(),
        model_used: input.model.clone(),
    };

    log_info(&format!(
        "Transcription complete. Output: {} ({} chars)",
        output.output_path, output.transcription.len()
    ));

    // Serialize output to JS value
    let output_json = serde_json::to_string(&output).map_err(|e| {
        let err = SttError::ApiError(format!("Failed to serialize output: {}", e));
        log_error(&err.to_string());
        JsValue::from_str(&err.to_string())
    })?;

    Ok(JsValue::from_str(&output_json))
}

/// Transcribe with fallback model
#[wasm_bindgen]
pub async fn transcribe_fallback(input_json: &str) -> Result<JsValue, JsValue> {
    log_info("Starting STT transcription (fallback mode)...");

    // Parse input
    let mut input: SttInput = serde_json::from_str(input_json).map_err(|e| {
        let err = SttError::InvalidInput(format!("Failed to parse input JSON: {}", e));
        log_error(&err.to_string());
        JsValue::from_str(&err.to_string())
    })?;

    // Use fallback model
    input.model = "openai/whisper-large-v3".to_string();

    // Validate input
    validate_input(&input).map_err(|e| {
        log_error(&e.to_string());
        JsValue::from_str(&e.to_string())
    })?;

    log_info(&format!(
        "Transcribing audio from: {} using fallback model: {}",
        input.audio_path, input.model
    ));

    // Read audio file
    let audio_data = read_audio_file(&input.audio_path)
        .await
        .map_err(|e| {
            log_error(&e.to_string());
            JsValue::from_str(&e.to_string())
        })?;

    // Convert audio to base64
    let audio_base64 = BASE64.encode(&audio_data);

    // Call Chutes.ai API for transcription with fallback model
    let (transcription, language_detected, duration, confidence) = call_chutes_stt_api(
        &audio_base64,
        &input.mime_type,
        &input.model,
        input.language.as_deref(),
    )
    .await
    .map_err(|e| {
        log_error(&e.to_string());
        JsValue::from_str(&e.to_string())
    })?;

    // Write transcription to output file
    write_transcription_file(&input.output_path, &transcription)
        .await
        .map_err(|e| {
            log_error(&e.to_string());
            JsValue::from_str(&e.to_string())
        })?;

    // Build output
    let output = SttOutput {
        transcription: transcription.clone(),
        confidence,
        language_detected,
        duration_ms: duration,
        output_path: input.output_path.clone(),
        model_used: input.model.clone(),
    };

    log_info(&format!(
        "Fallback transcription complete. Output: {} ({} chars)",
        output.output_path, output.transcription.len()
    ));

    // Serialize output to JS value
    let output_json = serde_json::to_string(&output).map_err(|e| {
        let err = SttError::ApiError(format!("Failed to serialize output: {}", e));
        log_error(&err.to_string());
        JsValue::from_str(&err.to_string())
    })?;

    Ok(JsValue::from_str(&output_json))
}

/// Get the default model
#[wasm_bindgen]
pub fn get_default_model() -> String {
    default_model()
}

/// Get the default MIME type
#[wasm_bindgen]
pub fn get_default_mime_type() -> String {
    default_mime_type()
}

/// Validate a path is within allowed scopes
#[wasm_bindgen]
pub fn validate_path(path: &str, path_type: &str) -> Result<bool, JsValue> {
    match path_type {
        "ro" => {
            let ro_scopes: &[&str] = &["/agents/mentor/", "/tmp/stt_input/"];
            Ok(validate_path_scope(path, ro_scopes).is_ok())
        }
        "rw" => {
            let rw_scopes: &[&str] = &["/tmp/stt_output/", "/tmp/stt_cache/"];
            Ok(validate_path_scope(path, rw_scopes).is_ok())
        }
        _ => Err(JsValue::from_str(
            "Invalid path_type, must be 'ro' or 'rw'",
        )),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_values() {
        assert_eq!(default_mime_type(), "audio/ogg");
        assert_eq!(default_model(), "openai/whisper-large-v3-turbo");
    }

    #[test]
    fn test_validate_path_scope() {
        let ro_scopes: &[&str] = &["/agents/mentor/", "/tmp/stt_input/"];

        assert!(validate_path_scope("/agents/mentor/audio.wav", ro_scopes).is_ok());
        assert!(validate_path_scope("/tmp/stt_input/audio.ogg", ro_scopes).is_ok());
        assert!(validate_path_scope("/etc/passwd", ro_scopes).is_err());
        assert!(validate_path_scope("/workspace/file.wav", ro_scopes).is_err());
    }

    #[test]
    fn test_validate_input() {
        let valid_input = SttInput {
            audio_path: "/tmp/stt_input/audio.ogg".to_string(),
            output_path: "/tmp/stt_output/transcription.txt".to_string(),
            mime_type: "audio/ogg".to_string(),
            language: Some("en".to_string()),
            model: "openai/whisper-large-v3-turbo".to_string(),
        };

        assert!(validate_input(&valid_input).is_ok());

        let invalid_ro_path = SttInput {
            audio_path: "/etc/passwd".to_string(),
            ..valid_input.clone()
        };
        assert!(validate_input(&invalid_ro_path).is_err());

        let invalid_rw_path = SttInput {
            output_path: "/workspace/output.txt".to_string(),
            ..valid_input.clone()
        };
        assert!(validate_input(&invalid_rw_path).is_err());

        let invalid_format = SttInput {
            mime_type: "audio/flac".to_string(),
            ..valid_input.clone()
        };
        assert!(validate_input(&invalid_format).is_err());
    }

    #[test]
    fn test_mime_type_to_format() {
        assert_eq!(mime_type_to_format("audio/ogg"), "ogg");
        assert_eq!(mime_type_to_format("audio/wav"), "wav");
        assert_eq!(mime_type_to_format("audio/mp3"), "mp3");
        assert_eq!(mime_type_to_format("audio/mp4"), "mp4");
        assert_eq!(mime_type_to_format("audio/webm"), "webm");
        assert_eq!(mime_type_to_format("audio/unknown"), "ogg");
    }
}
