use std::collections::BTreeMap;
use thiserror::Error;

#[derive(Debug, Error, PartialEq)]
pub enum LedgerError {
    #[error("Tool call with canonical ID {0} already exists")]
    DuplicateCanonicalId(String),
    #[error("Tool call with ingress ID {0} not found")]
    IngressIdNotFound(String),
    #[error("Tool call with provider ID {0} not found")]
    ProviderIdNotFound(String),
}

/// Recorded mapping for a single tool call execution across protocols.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ToolCallEntry {
    pub canonical_id: String,
    pub ingress_id: String,
    pub provider_id: String,
    pub tool_name: String,
    pub created_at: u64,
}

/// Session-scoped ledger managing identity correlation between ingress protocols
/// (Codex Responses item ID, Anthropic tool_use_id, OpenAI call_id) and provider IDs.
#[derive(Debug, Default, Clone)]
pub struct ToolCallIdLedger {
    by_canonical: BTreeMap<String, ToolCallEntry>,
    by_ingress: BTreeMap<String, String>,   // ingress_id -> canonical_id
    by_provider: BTreeMap<String, String>,  // provider_id -> canonical_id
}

impl ToolCallIdLedger {
    pub fn new() -> Self {
        Self::default()
    }

    /// Register a newly originated tool call.
    pub fn register(
        &mut self,
        canonical_id: impl Into<String>,
        ingress_id: impl Into<String>,
        provider_id: impl Into<String>,
        tool_name: impl Into<String>,
        timestamp: u64,
    ) -> Result<ToolCallEntry, LedgerError> {
        let canonical_id = canonical_id.into();
        let ingress_id = ingress_id.into();
        let provider_id = provider_id.into();
        let tool_name = tool_name.into();

        if self.by_canonical.contains_key(&canonical_id) {
            return Err(LedgerError::DuplicateCanonicalId(canonical_id));
        }

        let entry = ToolCallEntry {
            canonical_id: canonical_id.clone(),
            ingress_id: ingress_id.clone(),
            provider_id: provider_id.clone(),
            tool_name,
            created_at: timestamp,
        };

        self.by_ingress.insert(ingress_id, canonical_id.clone());
        self.by_provider.insert(provider_id, canonical_id.clone());
        self.by_canonical.insert(canonical_id, entry.clone());

        Ok(entry)
    }

    /// Look up a registered tool call by its client ingress ID when tool results arrive.
    pub fn resolve_ingress(&self, ingress_id: &str) -> Result<&ToolCallEntry, LedgerError> {
        let canonical_id = self
            .by_ingress
            .get(ingress_id)
            .ok_or_else(|| LedgerError::IngressIdNotFound(ingress_id.to_string()))?;
        self.by_canonical
            .get(canonical_id)
            .ok_or_else(|| LedgerError::IngressIdNotFound(ingress_id.to_string()))
    }

    /// Look up a registered tool call by the target provider's ID.
    pub fn resolve_provider(&self, provider_id: &str) -> Result<&ToolCallEntry, LedgerError> {
        let canonical_id = self
            .by_provider
            .get(provider_id)
            .ok_or_else(|| LedgerError::ProviderIdNotFound(provider_id.to_string()))?;
        self.by_canonical
            .get(canonical_id)
            .ok_or_else(|| LedgerError::ProviderIdNotFound(provider_id.to_string()))
    }

    /// Total number of active registered tool calls in this session.
    pub fn len(&self) -> usize {
        self.by_canonical.len()
    }

    pub fn is_empty(&self) -> bool {
        self.by_canonical.is_empty()
    }
}
