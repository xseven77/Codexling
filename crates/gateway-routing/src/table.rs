use std::collections::BTreeMap;
use gateway_ir::{Fidelity, ModelSelector};
use thiserror::Error;
use crate::alias::{ModelAliasDefinition, ResolvedTarget};

#[derive(Debug, Error, PartialEq, Eq)]
pub enum RoutingError {
    #[error("Alias '{0}' not found in route table")]
    AliasNotFound(String),
    #[error("No candidates for alias '{0}' satisfy the required capabilities")]
    NoMatchingCandidate(String),
}

/// In-memory route table mapping model selectors and session stickiness to upstream targets.
#[derive(Debug, Default, Clone)]
pub struct RouteTable {
    aliases: BTreeMap<String, ModelAliasDefinition>,
    sticky_sessions: BTreeMap<String, ResolvedTarget>,
}

impl RouteTable {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn register_alias(&mut self, def: ModelAliasDefinition) {
        self.aliases.insert(def.alias.clone(), def);
    }

    pub fn set_sticky_session(&mut self, session_id: impl Into<String>, target: ResolvedTarget) {
        let mut t = target;
        t.is_sticky = true;
        self.sticky_sessions.insert(session_id.into(), t);
    }

    pub fn get_sticky_session(&self, session_id: &str) -> Option<&ResolvedTarget> {
        self.sticky_sessions.get(session_id)
    }

    pub fn clear_sticky_session(&mut self, session_id: &str) {
        self.sticky_sessions.remove(session_id);
    }

    /// Resolve a ModelSelector into a concrete Provider and Model ID.
    pub fn resolve(
        &self,
        selector: &ModelSelector,
        session_id: Option<&str>,
    ) -> Result<ResolvedTarget, RoutingError> {
        // Check session stickiness first
        if let Some(sid) = session_id {
            if let Some(target) = self.sticky_sessions.get(sid) {
                return Ok(target.clone());
            }
        }

        match selector {
            ModelSelector::Exact { provider, model } => Ok(ResolvedTarget {
                provider: provider.clone(),
                model: model.clone(),
                fidelity: Fidelity::Native,
                is_sticky: false,
            }),
            ModelSelector::Alias(alias) => {
                if let Some(def) = self.aliases.get(alias) {
                    // Filter candidates that meet required capabilities
                    let mut valid_candidates: Vec<_> = def
                        .candidates
                        .iter()
                        .filter(|c| def.required_capabilities.is_subset_of(&c.capabilities))
                        .collect();

                    // Sort by priority descending (higher is preferred)
                    valid_candidates.sort_by(|a, b| b.priority.cmp(&a.priority));

                    if let Some(chosen) = valid_candidates.first() {
                        return Ok(ResolvedTarget {
                            provider: chosen.provider.clone(),
                            model: chosen.model.clone(),
                            fidelity: Fidelity::Native,
                            is_sticky: false,
                        });
                    }
                }

                // Dynamic Pass-Through Fallback:
                // Allows ANY model to be requested directly (e.g. gemini-3.7-flash, deepseek-v4-pro)
                let lower = alias.to_lowercase();
                let provider = if lower.contains("gemini") {
                    "gemini"
                } else if lower.contains("deepseek") {
                    "deepseek"
                } else if lower.contains("claude") {
                    "anthropic"
                } else if lower.contains("gpt") || lower.contains("codex") || lower.starts_with("o1") || lower.starts_with("o3") || lower.starts_with("o4") || lower.starts_with("o5") {
                    "openai"
                } else {
                    "default"
                };

                Ok(ResolvedTarget {
                    provider: provider.into(),
                    model: alias.clone(),
                    fidelity: Fidelity::Native,
                    is_sticky: false,
                })
            }
        }
    }
}
