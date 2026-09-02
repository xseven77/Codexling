pub mod accumulator;
pub mod event;

pub use accumulator::{AccumulatorError, StreamAccumulator};
pub use event::{
    ItemCompleted, ItemStarted, ReasoningDelta, ResponseCompleted, ResponseStarted, StreamEvent,
    TextDelta, ToolArgumentsDelta, ToolCallCompleted, ToolCallStarted,
};

#[cfg(test)]
mod tests {
    use super::*;
    use gateway_ir::{ContentBlock, FinishReason, Usage};

    #[test]
    fn test_stream_accumulation_into_response() {
        let mut acc = StreamAccumulator::new();

        acc.process(&StreamEvent::ResponseStarted(ResponseStarted {
            sequence: 1,
            response_id: "resp_test".into(),
            model: "coding-smart".into(),
            created_at: 1724900000,
        }))
        .unwrap();

        acc.process(&StreamEvent::TextDelta(TextDelta {
            sequence: 2,
            item_id: "msg_1".into(),
            text: "Hello, ".into(),
        }))
        .unwrap();

        acc.process(&StreamEvent::TextDelta(TextDelta {
            sequence: 3,
            item_id: "msg_1".into(),
            text: "world!".into(),
        }))
        .unwrap();

        acc.process(&StreamEvent::ToolCallStarted(ToolCallStarted {
            sequence: 4,
            item_id: "tool_1".into(),
            call_id: "call_abc".into(),
            name: "read_file".into(),
            index: 0,
        }))
        .unwrap();

        acc.process(&StreamEvent::ToolArgumentsDelta(ToolArgumentsDelta {
            sequence: 5,
            call_id: "call_abc".into(),
            delta: "{\"path\": ".into(),
        }))
        .unwrap();

        acc.process(&StreamEvent::ToolArgumentsDelta(ToolArgumentsDelta {
            sequence: 6,
            call_id: "call_abc".into(),
            delta: "\"README.md\"}".into(),
        }))
        .unwrap();

        acc.process(&StreamEvent::UsageUpdated(Usage {
            input_tokens: 15,
            output_tokens: 28,
            reasoning_tokens: None,
            cached_tokens: None,
        }))
        .unwrap();

        acc.process(&StreamEvent::ResponseCompleted(ResponseCompleted {
            sequence: 7,
            finish_reason: FinishReason::ToolCalls,
        }))
        .unwrap();

        let response = acc.finish().unwrap();
        assert_eq!(response.response_id, "resp_test");
        assert_eq!(response.model, "coding-smart");
        assert_eq!(response.finish_reason, FinishReason::ToolCalls);
        assert_eq!(response.items.len(), 2);

        match &response.items[0] {
            ContentBlock::Text(t) => assert_eq!(t.text, "Hello, world!"),
            _ => panic!("Expected text block"),
        }

        match &response.items[1] {
            ContentBlock::ToolCall(tc) => {
                assert_eq!(tc.name, "read_file");
                assert_eq!(tc.arguments, "{\"path\": \"README.md\"}");
            }
            _ => panic!("Expected tool call block"),
        }
    }

    #[test]
    fn test_non_monotonic_sequence_rejected() {
        let mut acc = StreamAccumulator::new();
        acc.process(&StreamEvent::ResponseStarted(ResponseStarted {
            sequence: 5,
            response_id: "resp_1".into(),
            model: "model".into(),
            created_at: 0,
        }))
        .unwrap();

        let err = acc
            .process(&StreamEvent::TextDelta(TextDelta {
                sequence: 4,
                item_id: "1".into(),
                text: "a".into(),
            }))
            .unwrap_err();

        assert_eq!(
            err,
            AccumulatorError::SequenceOutdated {
                expected: 5,
                received: 4
            }
        );
    }
}
