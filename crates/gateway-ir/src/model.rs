use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;

/// Specification of target model, either as a logical alias (e.g. "coding-smart")
/// or an explicit provider-qualified model ID (e.g. "gemini/gemini-2.5-pro").
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(tag = "kind", content = "value")]
pub enum ModelSelector {
    /// Logical alias resolved via Gateway route table.
    Alias(String),
    /// Explicit provider and upstream model ID.
    Exact {
        provider: String,
        model: String,
    },
}

impl ModelSelector {
    pub fn alias(name: impl Into<String>) -> Self {
        Self::Alias(name.into())
    }

    pub fn exact(provider: impl Into<String>, model: impl Into<String>) -> Self {
        Self::Exact {
            provider: provider.into(),
            model: model.into(),
        }
    }

    pub fn raw_name(&self) -> &str {
        match self {
            Self::Alias(a) => a,
            Self::Exact { model, .. } => model,
        }
    }
}

/// Sampling and generation hyperparameters.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct GenerationConfig {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub temperature: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub top_p: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_output_tokens: Option<u64>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub stop_sequences: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub presence_penalty: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub frequency_penalty: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reasoning_effort: Option<String>,
}

/// Known model capability flags.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Capability {
    NativeTools,
    ParallelTools,
    StructuredOutput,
    Reasoning,
    ReasoningStream,
    PromptCache,
    MultimodalImage,
    MultimodalAudio,
}

/// Set of capabilities requested by a client or required by a route alias.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct CapabilitySet(pub BTreeSet<Capability>);

impl CapabilitySet {
    pub fn new() -> Self {
        Self(BTreeSet::new())
    }

    pub fn with(mut self, cap: Capability) -> Self {
        self.0.insert(cap);
        self
    }

    pub fn contains(&self, cap: Capability) -> bool {
        self.0.contains(&cap)
    }

    pub fn is_subset_of(&self, other: &CapabilitySet) -> bool {
        self.0.is_subset(&other.0)
    }
}
