pub mod alias;
pub mod table;

pub use alias::{ModelAliasDefinition, ResolvedTarget, RouteCandidate};
pub use table::{RoutingError, RouteTable};

#[cfg(test)]
mod tests {
    use super::*;
    use gateway_ir::{Capability, CapabilitySet, ModelSelector};

    #[test]
    fn test_alias_resolution_with_capabilities_and_priority() {
        let mut table = RouteTable::new();

        let req_caps = CapabilitySet::new()
            .with(Capability::NativeTools)
            .with(Capability::Reasoning);

        let mut alias = ModelAliasDefinition::new("coding-smart").require(req_caps);

        // Candidate 1: has both capabilities, priority 10
        alias = alias.add_candidate(
            RouteCandidate::new("gemini", "gemini-2.5-pro")
                .with_capabilities(
                    CapabilitySet::new()
                        .with(Capability::NativeTools)
                        .with(Capability::Reasoning)
                        .with(Capability::ReasoningStream),
                )
                .with_priority(10),
        );

        // Candidate 2: lacks reasoning, priority 20 (higher priority, but fails capability requirement)
        alias = alias.add_candidate(
            RouteCandidate::new("deepseek", "deepseek-chat")
                .with_capabilities(CapabilitySet::new().with(Capability::NativeTools))
                .with_priority(20),
        );

        table.register_alias(alias);

        // Resolve alias
        let resolved = table
            .resolve(&ModelSelector::alias("coding-smart"), None)
            .unwrap();
        assert_eq!(resolved.provider, "gemini");
        assert_eq!(resolved.model, "gemini-2.5-pro");
        assert_eq!(resolved.is_sticky, false);
    }

    #[test]
    fn test_session_stickiness_overrides_alias() {
        let mut table = RouteTable::new();

        let alias = ModelAliasDefinition::new("coding-fast").add_candidate(
            RouteCandidate::new("openai", "gpt-4o-mini").with_priority(10),
        );
        table.register_alias(alias);

        let sticky_target = ResolvedTarget {
            provider: "gemini".into(),
            model: "gemini-2.5-flash".into(),
            fidelity: gateway_ir::Fidelity::Native,
            is_sticky: true,
        };
        table.set_sticky_session("session_123", sticky_target);

        // Normal lookup without session ID resolves to alias candidate
        let normal = table
            .resolve(&ModelSelector::alias("coding-fast"), None)
            .unwrap();
        assert_eq!(normal.provider, "openai");

        // Lookup with session_123 resolves to sticky target
        let sticky = table
            .resolve(&ModelSelector::alias("coding-fast"), Some("session_123"))
            .unwrap();
        assert_eq!(sticky.provider, "gemini");
        assert_eq!(sticky.model, "gemini-2.5-flash");
        assert_eq!(sticky.is_sticky, true);
    }

    #[test]
    fn test_arbitrary_unregistered_model_dynamic_passthrough() {
        let table = RouteTable::new();

        // 1. Unregistered Gemini model (e.g. gemini-3.7-flash)
        let gemini_target = table
            .resolve(&ModelSelector::alias("gemini-3.7-flash"), None)
            .unwrap();
        assert_eq!(gemini_target.provider, "gemini");
        assert_eq!(gemini_target.model, "gemini-3.7-flash");

        // 2. Unregistered DeepSeek model (e.g. deepseek-v4-pro)
        let ds_target = table
            .resolve(&ModelSelector::alias("deepseek-v4-pro"), None)
            .unwrap();
        assert_eq!(ds_target.provider, "deepseek");
        assert_eq!(ds_target.model, "deepseek-v4-pro");

        // 3. Unregistered Claude model
        let claude_target = table
            .resolve(&ModelSelector::alias("claude-4-ultra"), None)
            .unwrap();
        assert_eq!(claude_target.provider, "anthropic");
        assert_eq!(claude_target.model, "claude-4-ultra");

        // 4. OpenAI / Codex GPT-5 model
        let gpt5_target = table
            .resolve(&ModelSelector::alias("gpt-5"), None)
            .unwrap();
        assert_eq!(gpt5_target.provider, "openai");
        assert_eq!(gpt5_target.model, "gpt-5");

        let gpt5_codex = table
            .resolve(&ModelSelector::alias("gpt-5-codex"), None)
            .unwrap();
        assert_eq!(gpt5_codex.provider, "openai");
        assert_eq!(gpt5_codex.model, "gpt-5-codex");
    }
}
