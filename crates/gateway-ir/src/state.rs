use serde::{Deserialize, Serialize};

/// Provider identifier (e.g. "openai", "anthropic", "gemini", "deepseek").
pub type ProviderId = String;

/// Scopes for provider state persistence and replaying.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(tag = "type", content = "id")]
pub enum StateScope {
    /// Applies to the entire request turn.
    Request,
    /// Scoped to a specific message item.
    Item(String),
    /// Scoped to a specific tool call execution.
    ToolCall(String),
    /// Scoped across a multi-turn conversation session.
    Conversation(String),
}

/// Replay policies defining when provider state may be sent back to upstream.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum ReplayPolicy {
    /// Replay on all subsequent turns within scope.
    #[default]
    Always,
    /// Only replay if the target model is identical.
    SameModelOnly,
    /// Replay if the target provider is identical (even if sub-model differs).
    SameProviderOnly,
    /// Never replay automatically (informational only).
    Never,
}

/// Encapsulates opaque provider state that must be preserved across turns
/// (e.g., Anthropic thinking signature, Gemini thought signatures, Codex item IDs).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProviderState {
    pub provider: ProviderId,
    pub scope: StateScope,
    pub key: String,
    pub value: serde_json::Value,
    #[serde(default)]
    pub replay: ReplayPolicy,
}

impl ProviderState {
    pub fn new(
        provider: impl Into<ProviderId>,
        scope: StateScope,
        key: impl Into<String>,
        value: serde_json::Value,
    ) -> Self {
        Self {
            provider: provider.into(),
            scope,
            key: key.into(),
            value,
            replay: ReplayPolicy::Always,
        }
    }

    pub fn with_replay(mut self, replay: ReplayPolicy) -> Self {
        self.replay = replay;
        self
    }
}

/// Encoding format for raw bytes in ProviderOpaque payloads.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum OpaqueEncoding {
    #[default]
    Utf8,
    Base64,
    Hex,
    RawBytes,
}

/// Opaque data block that cannot be universally standardized across providers
/// but must not be lost or converted to plain text (e.g. encrypted reasoning, binary state).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProviderOpaque {
    pub provider: ProviderId,
    pub kind: String,
    #[serde(default)]
    pub encoding: OpaqueEncoding,
    pub data: Vec<u8>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub integrity: Option<String>,
}

impl ProviderOpaque {
    pub fn from_utf8(
        provider: impl Into<ProviderId>,
        kind: impl Into<String>,
        text: impl Into<String>,
    ) -> Self {
        Self {
            provider: provider.into(),
            kind: kind.into(),
            encoding: OpaqueEncoding::Utf8,
            data: text.into().into_bytes(),
            integrity: None,
        }
    }

    pub fn from_bytes(
        provider: impl Into<ProviderId>,
        kind: impl Into<String>,
        data: Vec<u8>,
    ) -> Self {
        Self {
            provider: provider.into(),
            kind: kind.into(),
            encoding: OpaqueEncoding::RawBytes,
            data,
            integrity: None,
        }
    }
}
