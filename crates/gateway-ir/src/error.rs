use serde::{Deserialize, Serialize};
use thiserror::Error;

/// Standard normalized error codes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ErrorCode {
    InvalidRequest,
    Unauthorized,
    ModelNotFound,
    CapabilityMismatch,
    RateLimited,
    ContextLengthExceeded,
    ProviderUnavailable,
    ProviderTimeout,
    StreamDisconnected,
    InternalError,
}

/// Normalized canonical error emitted across protocols.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Error)]
#[error("{message} (code: {code:?})")]
pub struct CanonicalError {
    pub code: ErrorCode,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub param: Option<String>,
    pub status_code: u16,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provider_raw: Option<serde_json::Value>,
}

impl CanonicalError {
    pub fn new(code: ErrorCode, message: impl Into<String>, status_code: u16) -> Self {
        Self {
            code,
            message: message.into(),
            param: None,
            status_code,
            provider_raw: None,
        }
    }

    pub fn invalid_request(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::InvalidRequest, message, 400)
    }

    pub fn unauthorized(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::Unauthorized, message, 401)
    }

    pub fn model_not_found(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::ModelNotFound, message, 404)
    }

    pub fn rate_limited(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::RateLimited, message, 429)
    }

    pub fn internal(message: impl Into<String>) -> Self {
        Self::new(ErrorCode::InternalError, message, 500)
    }

    pub fn with_raw(mut self, raw: serde_json::Value) -> Self {
        self.provider_raw = Some(raw);
        self
    }
}
