use gateway_ir::{CanonicalError, FinishReason, Role, Usage};
use serde::{Deserialize, Serialize};

/// Header event initiating a streaming model response.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ResponseStarted {
    pub sequence: u64,
    pub response_id: String,
    pub model: String,
    pub created_at: u64,
}

/// Indicates a new output item (message, reasoning or tool call block) has begun.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ItemStarted {
    pub sequence: u64,
    pub item_id: String,
    pub index: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub role: Option<Role>,
}

/// Incremental text content delta.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TextDelta {
    pub sequence: u64,
    pub item_id: String,
    pub text: String,
}

/// Incremental reasoning / chain-of-thought delta.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReasoningDelta {
    pub sequence: u64,
    pub item_id: String,
    pub text: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub signature: Option<String>,
}

/// Indicates a model has begun calling a tool.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ToolCallStarted {
    pub sequence: u64,
    pub item_id: String,
    pub call_id: String,
    pub name: String,
    pub index: usize,
}

/// Incremental raw JSON text fragment of tool arguments.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ToolArgumentsDelta {
    pub sequence: u64,
    pub call_id: String,
    pub delta: String,
}

/// Indicates a tool call's arguments have completed and were verified.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ToolCallCompleted {
    pub sequence: u64,
    pub call_id: String,
    pub name: String,
    pub arguments: String,
}

/// Indicates an item block has concluded.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ItemCompleted {
    pub sequence: u64,
    pub item_id: String,
}

/// Final normal completion event for a response stream.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct ResponseCompleted {
    pub sequence: u64,
    pub finish_reason: FinishReason,
}

/// Canonical stream event stream definition.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", content = "data")]
pub enum StreamEvent {
    ResponseStarted(ResponseStarted),
    ItemStarted(ItemStarted),
    TextDelta(TextDelta),
    ReasoningDelta(ReasoningDelta),
    ToolCallStarted(ToolCallStarted),
    ToolArgumentsDelta(ToolArgumentsDelta),
    ToolCallCompleted(ToolCallCompleted),
    ItemCompleted(ItemCompleted),
    UsageUpdated(Usage),
    ResponseCompleted(ResponseCompleted),
    ResponseFailed(CanonicalError),
    KeepAlive,
}

impl StreamEvent {
    pub fn sequence(&self) -> Option<u64> {
        match self {
            Self::ResponseStarted(e) => Some(e.sequence),
            Self::ItemStarted(e) => Some(e.sequence),
            Self::TextDelta(e) => Some(e.sequence),
            Self::ReasoningDelta(e) => Some(e.sequence),
            Self::ToolCallStarted(e) => Some(e.sequence),
            Self::ToolArgumentsDelta(e) => Some(e.sequence),
            Self::ToolCallCompleted(e) => Some(e.sequence),
            Self::ItemCompleted(e) => Some(e.sequence),
            Self::ResponseCompleted(e) => Some(e.sequence),
            Self::UsageUpdated(_) | Self::ResponseFailed(_) | Self::KeepAlive => None,
        }
    }

    pub fn is_terminal(&self) -> bool {
        matches!(self, Self::ResponseCompleted(_) | Self::ResponseFailed(_))
    }
}
