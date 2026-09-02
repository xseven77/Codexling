use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use crate::model::{CapabilitySet, GenerationConfig, ModelSelector};
use crate::state::{ProviderOpaque, ProviderState};
use crate::tool::{ToolChoice, ToolDefinition, ToolCall, ToolResult};

/// Standard message role.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Role {
    System,
    Developer,
    User,
    Assistant,
    Tool,
}

/// Plain text content part with optional prompt caching flag.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TextBlock {
    pub text: String,
    #[serde(default)]
    pub cache_control: bool,
}

impl TextBlock {
    pub fn new(text: impl Into<String>) -> Self {
        Self {
            text: text.into(),
            cache_control: false,
        }
    }
}

/// Multimodal image content part.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ImageBlock {
    pub mime_type: String,
    /// Base64-encoded binary image data or remote HTTP URL.
    pub data: String,
}

/// Reasoning / chain-of-thought content block.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct ReasoningBlock {
    pub text: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub signature: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub opaque: Option<String>,
}

impl ReasoningBlock {
    pub fn new(text: impl Into<String>) -> Self {
        Self {
            text: text.into(),
            signature: None,
            opaque: None,
        }
    }

    pub fn with_signature(mut self, sig: impl Into<String>) -> Self {
        self.signature = Some(sig.into());
        self
    }
}

/// Heterogeneous content blocks within a message.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", content = "content")]
pub enum ContentBlock {
    Text(TextBlock),
    Image(ImageBlock),
    ToolCall(ToolCall),
    ToolResult(ToolResult),
    Reasoning(ReasoningBlock),
    ProviderOpaque(ProviderOpaque),
}

impl ContentBlock {
    pub fn text(text: impl Into<String>) -> Self {
        Self::Text(TextBlock::new(text))
    }

    pub fn tool_call(call: ToolCall) -> Self {
        Self::ToolCall(call)
    }

    pub fn tool_result(result: ToolResult) -> Self {
        Self::ToolResult(result)
    }

    pub fn reasoning(reasoning: ReasoningBlock) -> Self {
        Self::Reasoning(reasoning)
    }
}

/// Single conversational message turn.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Message {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<String>,
    pub role: Role,
    pub content: Vec<ContentBlock>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub provider_state: Vec<ProviderState>,
}

impl Message {
    pub fn new(role: Role, content: Vec<ContentBlock>) -> Self {
        Self {
            id: None,
            role,
            content,
            provider_state: Vec::new(),
        }
    }

    pub fn user(text: impl Into<String>) -> Self {
        Self::new(Role::User, vec![ContentBlock::text(text)])
    }

    pub fn assistant(text: impl Into<String>) -> Self {
        Self::new(Role::Assistant, vec![ContentBlock::text(text)])
    }

    pub fn system(text: impl Into<String>) -> Self {
        Self::new(Role::System, vec![ContentBlock::text(text)])
    }

    pub fn developer(text: impl Into<String>) -> Self {
        Self::new(Role::Developer, vec![ContentBlock::text(text)])
    }

    pub fn with_id(mut self, id: impl Into<String>) -> Self {
        self.id = Some(id.into());
        self
    }
}

/// High-level input item in a multi-turn conversation (Responses API items model).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "item_type")]
pub enum InputItem {
    Message(Message),
    ToolResult(ToolResult),
    ProviderOpaque(ProviderOpaque),
}

impl InputItem {
    pub fn from_message(msg: Message) -> Self {
        Self::Message(msg)
    }

    pub fn as_message(&self) -> Option<&Message> {
        match self {
            Self::Message(m) => Some(m),
            _ => None,
        }
    }
}

/// Primary unified request representation passed through the Gateway core.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CanonicalRequest {
    pub request_id: String,
    pub model: ModelSelector,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub instructions: Vec<String>,
    pub items: Vec<InputItem>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub tools: Vec<ToolDefinition>,
    #[serde(default)]
    pub tool_choice: ToolChoice,
    #[serde(default)]
    pub generation: GenerationConfig,
    #[serde(default)]
    pub requested_capabilities: CapabilitySet,
    #[serde(default)]
    pub stream: bool,
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub metadata: BTreeMap<String, serde_json::Value>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub provider_state: Vec<ProviderState>,
}

impl CanonicalRequest {
    pub fn new(request_id: impl Into<String>, model: ModelSelector) -> Self {
        Self {
            request_id: request_id.into(),
            model,
            instructions: Vec::new(),
            items: Vec::new(),
            tools: Vec::new(),
            tool_choice: ToolChoice::Auto,
            generation: GenerationConfig::default(),
            requested_capabilities: CapabilitySet::default(),
            stream: false,
            metadata: BTreeMap::new(),
            provider_state: Vec::new(),
        }
    }
}

/// Token usage accounting.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct Usage {
    pub input_tokens: u64,
    pub output_tokens: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reasoning_tokens: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cached_tokens: Option<u64>,
}

/// Reason the model stopped generation.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FinishReason {
    Stop,
    Length,
    ToolCalls,
    ContentFilter,
    Error,
}

/// Complete non-streaming response output.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CanonicalResponse {
    pub response_id: String,
    pub model: String,
    pub items: Vec<ContentBlock>,
    pub finish_reason: FinishReason,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub usage: Option<Usage>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub provider_state: Vec<ProviderState>,
}
