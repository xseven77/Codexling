pub mod ledger;
pub mod telemetry;

pub use ledger::{LedgerError, ToolCallEntry, ToolCallIdLedger};
pub use telemetry::{
    BreakdownItem, BreakdownResponse, RequestsListResponse, TelemetryEvent, TelemetryQueryFilter,
    TelemetryStore, TelemetrySummary, TimeseriesBucket, TimeseriesResponse,
};


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tool_call_id_ledger_bidirectional_lookup() {
        let mut ledger = ToolCallIdLedger::new();

        ledger
            .register(
                "canon_call_101",
                "call_openai_xyz",
                "gemini_fc_part_789",
                "read_file",
                1000,
            )
            .unwrap();

        // Resolving ingress ID when agent sends back tool results
        let from_ingress = ledger.resolve_ingress("call_openai_xyz").unwrap();
        assert_eq!(from_ingress.canonical_id, "canon_call_101");
        assert_eq!(from_ingress.provider_id, "gemini_fc_part_789");
        assert_eq!(from_ingress.tool_name, "read_file");

        // Resolving provider ID when upstream provider responds
        let from_provider = ledger.resolve_provider("gemini_fc_part_789").unwrap();
        assert_eq!(from_provider.ingress_id, "call_openai_xyz");

        // Unknown lookup errors
        assert_eq!(
            ledger.resolve_ingress("call_unknown"),
            Err(LedgerError::IngressIdNotFound("call_unknown".into()))
        );
    }

    #[test]
    fn test_duplicate_canonical_id_rejected() {
        let mut ledger = ToolCallIdLedger::new();
        ledger
            .register("c1", "i1", "p1", "tool_a", 100)
            .unwrap();

        let err = ledger
            .register("c1", "i2", "p2", "tool_b", 101)
            .unwrap_err();

        assert_eq!(err, LedgerError::DuplicateCanonicalId("c1".into()));
    }
}
