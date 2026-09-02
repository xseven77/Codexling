use serde::{Deserialize, Serialize};
use crate::state::ProviderState;

/// Tool choice constraint specified by client.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum ToolChoice {
    #[default]
    Auto,
    None,
    Required,
    #[serde(untagged)]
    Specific(String),
}

/// Normalized tool definition exposed to models.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ToolDefinition {
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    pub parameters: serde_json::Value,
    #[serde(default)]
    pub strict: bool,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub provider_options: Vec<ProviderState>,
}

impl ToolDefinition {
    pub fn new(name: impl Into<String>, parameters: serde_json::Value) -> Self {
        Self {
            name: name.into(),
            description: None,
            parameters,
            strict: false,
            provider_options: Vec::new(),
        }
    }

    pub fn with_description(mut self, desc: impl Into<String>) -> Self {
        self.description = Some(desc.into());
        self
    }

    pub fn with_strict(mut self, strict: bool) -> Self {
        self.strict = strict;
        self
    }
}

/// Normalized tool execution requested by model.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ToolCall {
    pub id: String,
    pub name: String,
    /// Raw JSON arguments string as produced by the model or merged from stream chunks.
    pub arguments: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub provider_state: Vec<ProviderState>,
}

impl ToolCall {
    pub fn new(id: impl Into<String>, name: impl Into<String>, arguments: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            name: name.into(),
            arguments: arguments.into(),
            provider_state: Vec::new(),
        }
    }
}

/// Tool execution output returned by agent host.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ToolResult {
    pub call_id: String,
    pub output: String,
    #[serde(default)]
    pub is_error: bool,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub provider_state: Vec<ProviderState>,
}

impl ToolResult {
    pub fn success(call_id: impl Into<String>, output: impl Into<String>) -> Self {
        Self {
            call_id: call_id.into(),
            output: output.into(),
            is_error: false,
            provider_state: Vec::new(),
        }
    }

    pub fn error(call_id: impl Into<String>, output: impl Into<String>) -> Self {
        Self {
            call_id: call_id.into(),
            output: output.into(),
            is_error: true,
            provider_state: Vec::new(),
        }
    }
}
