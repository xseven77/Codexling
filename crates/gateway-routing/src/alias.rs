use gateway_ir::{CapabilitySet, Fidelity, ModelSelector};
use serde::{Deserialize, Serialize};

/// Target upstream candidate for an alias.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RouteCandidate {
    pub provider: String,
    pub model: String,
    #[serde(default)]
    pub capabilities: CapabilitySet,
    #[serde(default)]
    pub priority: usize,
}

impl RouteCandidate {
    pub fn new(provider: impl Into<String>, model: impl Into<String>) -> Self {
        Self {
            provider: provider.into(),
            model: model.into(),
            capabilities: CapabilitySet::default(),
            priority: 0,
        }
    }

    pub fn with_capabilities(mut self, caps: CapabilitySet) -> Self {
        self.capabilities = caps;
        self
    }

    pub fn with_priority(mut self, priority: usize) -> Self {
        self.priority = priority;
        self
    }
}

/// Declaration of a logical model alias.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModelAliasDefinition {
    pub alias: String,
    #[serde(default)]
    pub required_capabilities: CapabilitySet,
    #[serde(default)]
    pub candidates: Vec<RouteCandidate>,
}

impl ModelAliasDefinition {
    pub fn new(alias: impl Into<String>) -> Self {
        Self {
            alias: alias.into(),
            required_capabilities: CapabilitySet::default(),
            candidates: Vec::new(),
        }
    }

    pub fn require(mut self, caps: CapabilitySet) -> Self {
        self.required_capabilities = caps;
        self
    }

    pub fn add_candidate(mut self, candidate: RouteCandidate) -> Self {
        self.candidates.push(candidate);
        self
    }
}

/// Final resolution result from the Router.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ResolvedTarget {
    pub provider: String,
    pub model: String,
    pub fidelity: Fidelity,
    pub is_sticky: bool,
}

impl ResolvedTarget {
    pub fn to_selector(&self) -> ModelSelector {
        ModelSelector::exact(self.provider.clone(), self.model.clone())
    }
}
