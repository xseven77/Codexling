pub mod error;
pub mod message;
pub mod model;
pub mod state;
pub mod tool;
pub mod translation;

pub use error::{CanonicalError, ErrorCode};
pub use message::{
    CanonicalRequest, CanonicalResponse, ContentBlock, FinishReason, ImageBlock, InputItem,
    Message, ReasoningBlock, Role, TextBlock, Usage,
};
pub use model::{Capability, CapabilitySet, GenerationConfig, ModelSelector};
pub use state::{OpaqueEncoding, ProviderId, ProviderOpaque, ProviderState, ReplayPolicy, StateScope};
pub use tool::{ToolCall, ToolChoice, ToolDefinition, ToolResult};
pub use translation::{CompatibilityWarning, Fidelity, LossImpact, TranslationLoss, TranslationResult};

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_canonical_request_roundtrip() {
        let mut req = CanonicalRequest::new("req_123", ModelSelector::alias("coding-smart"));
        req.items.push(InputItem::from_message(Message::user("Hello agent")));
        req.tools.push(ToolDefinition::new(
            "read_file",
            serde_json::json!({
                "type": "object",
                "properties": {
                    "path": { "type": "string" }
                },
                "required": ["path"]
            }),
        ));

        let json = serde_json::to_string(&req).expect("serialize");
        let decoded: CanonicalRequest = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(req, decoded);
    }

    #[test]
    fn test_provider_state_preserved() {
        let state = ProviderState::new(
            "anthropic",
            StateScope::Item("item_01".into()),
            "thinking_signature",
            serde_json::json!("sig_abc123"),
        );
        let json = serde_json::to_string(&state).expect("serialize");
        let decoded: ProviderState = serde_json::from_str(&json).expect("deserialize");
        assert_eq!(state, decoded);
    }

    #[test]
    fn test_translation_loss_fidelity_downgrade() {
        let mut res = TranslationResult::native(42);
        assert_eq!(res.fidelity, Fidelity::Native);

        res.add_loss(TranslationLoss::new(
            "temperature",
            "Target provider does not support custom temperature",
            LossImpact::Minor,
        ));
        assert_eq!(res.fidelity, Fidelity::Compatible);

        res.add_loss(TranslationLoss::new(
            "parallel_tool_calls",
            "Target provider serializes tools",
            LossImpact::Critical,
        ));
        assert_eq!(res.fidelity, Fidelity::Degraded);
    }
}
