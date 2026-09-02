pub mod decoder;
pub mod encoder;
pub mod schema;

pub use decoder::decode_responses_request;
pub use encoder::{encode_responses_payload, encode_responses_stream_event};
pub use schema::{OpenAiResponsesPayload, OpenAiResponsesRequest, ResponsesInputItem};

#[cfg(test)]
mod tests {
    use super::*;
    use gateway_ir::{ContentBlock, FinishReason, InputItem, Role};
    use gateway_stream::event::{
        ResponseCompleted, ResponseStarted, TextDelta, ToolArgumentsDelta, ToolCallCompleted,
        ToolCallStarted,
    };
    use gateway_stream::StreamEvent;

    #[test]
    fn test_decode_codex_responses_request() {
        let json = r#"{
            "model": "coding-smart",
            "instructions": "You are a code refactoring assistant.",
            "input": [
                {
                    "type": "message",
                    "id": "msg_01",
                    "role": "user",
                    "content": [{"type": "input_text", "text": "Fix the compiler warning"}]
                },
                {
                    "type": "function_call",
                    "id": "call_item_01",
                    "call_id": "call_exec_999",
                    "name": "exec",
                    "arguments": "{\"cmd\":\"cargo check\"}"
                },
                {
                    "type": "function_call_output",
                    "id": "call_out_01",
                    "call_id": "call_exec_999",
                    "output": "warning: unused variable `x`"
                }
            ],
            "tools": [
                {
                    "type": "function",
                    "name": "exec",
                    "description": "Execute local shell command",
                    "parameters": {"type": "object", "properties": {"cmd": {"type": "string"}}}
                }
            ],
            "stream": true,
            "temperature": 0.0
        }"#;

        let raw: OpenAiResponsesRequest = serde_json::from_str(json).unwrap();
        let res = decode_responses_request(raw, "req_resp_test");

        assert_eq!(res.fidelity, gateway_ir::Fidelity::Native);
        let req = res.value;
        assert_eq!(req.request_id, "req_resp_test");
        assert_eq!(req.model.raw_name(), "coding-smart");
        assert_eq!(req.instructions.len(), 1);
        assert_eq!(req.instructions[0], "You are a code refactoring assistant.");
        assert_eq!(req.stream, true);
        assert_eq!(req.tools.len(), 1);
        assert_eq!(req.tools[0].name, "exec");

        // Verify items: 1 user message, 1 assistant message with tool call, 1 tool result
        assert_eq!(req.items.len(), 3);

        match &req.items[0] {
            InputItem::Message(m) => {
                assert_eq!(m.id.as_deref(), Some("msg_01"));
                assert_eq!(m.role, Role::User);
                match &m.content[0] {
                    ContentBlock::Text(t) => assert_eq!(t.text, "Fix the compiler warning"),
                    _ => panic!("Expected text block"),
                }
            }
            _ => panic!("Expected message"),
        }

        match &req.items[1] {
            InputItem::Message(m) => {
                assert_eq!(m.role, Role::Assistant);
                match &m.content[0] {
                    ContentBlock::ToolCall(tc) => {
                        assert_eq!(tc.id, "call_exec_999");
                        assert_eq!(tc.name, "exec");
                        assert_eq!(tc.arguments, "{\"cmd\":\"cargo check\"}");
                    }
                    _ => panic!("Expected tool call block"),
                }
            }
            _ => panic!("Expected message"),
        }

        match &req.items[2] {
            InputItem::ToolResult(tr) => {
                assert_eq!(tr.call_id, "call_exec_999");
                assert_eq!(tr.output, "warning: unused variable `x`");
            }
            _ => panic!("Expected tool result"),
        }
    }

    #[test]
    fn test_encode_responses_sse_stream() {
        let resp_id = "resp_codex_001";
        let model = "coding-smart";

        // 1. response.created
        let ev1 = StreamEvent::ResponseStarted(ResponseStarted {
            sequence: 1,
            response_id: resp_id.into(),
            model: model.into(),
            created_at: 1724900100,
        });
        let chunks1 = encode_responses_stream_event(&ev1, resp_id, model);
        assert_eq!(chunks1.len(), 1);
        assert!(chunks1[0].starts_with("event: response.created\n"));

        // 2. output_text.delta
        let ev2 = StreamEvent::TextDelta(TextDelta {
            sequence: 2,
            item_id: "item_01".into(),
            text: "Let me check".into(),
        });
        let chunks2 = encode_responses_stream_event(&ev2, resp_id, model);
        assert_eq!(chunks2.len(), 1);
        assert!(chunks2[0].starts_with("event: response.output_text.delta\n"));

        // 3. function_call started & delta & completed
        let ev3 = StreamEvent::ToolCallStarted(ToolCallStarted {
            sequence: 3,
            item_id: "item_tool_01".into(),
            call_id: "call_99".into(),
            name: "exec".into(),
            index: 1,
        });
        let chunks3 = encode_responses_stream_event(&ev3, resp_id, model);
        assert_eq!(chunks3.len(), 1);
        assert!(chunks3[0].starts_with("event: response.output_item.added\n"));
        assert!(chunks3[0].contains("\"type\":\"function_call\""));

        let ev4 = StreamEvent::ToolArgumentsDelta(ToolArgumentsDelta {
            sequence: 4,
            call_id: "call_99".into(),
            delta: "{\"cmd\":\"ls\"}".into(),
        });
        let chunks4 = encode_responses_stream_event(&ev4, resp_id, model);
        assert_eq!(chunks4.len(), 1);
        assert!(chunks4[0].starts_with("event: response.function_call_arguments.delta\n"));

        let ev5 = StreamEvent::ToolCallCompleted(ToolCallCompleted {
            sequence: 5,
            call_id: "call_99".into(),
            name: "exec".into(),
            arguments: "{\"cmd\":\"ls\"}".into(),
        });
        let chunks5 = encode_responses_stream_event(&ev5, resp_id, model);
        assert_eq!(chunks5.len(), 1);
        assert!(chunks5[0].starts_with("event: response.output_item.done\n"));

        // 4. response.completed
        let ev6 = StreamEvent::ResponseCompleted(ResponseCompleted {
            sequence: 6,
            finish_reason: FinishReason::ToolCalls,
        });
        let chunks6 = encode_responses_stream_event(&ev6, resp_id, model);
        assert_eq!(chunks6.len(), 1);
        assert!(chunks6[0].starts_with("event: response.completed\n"));
    }

    #[test]
    fn test_fixture_request_codex_items() {
        let fixture = include_str!("../../../fixtures/protocols/openai-responses/request_codex_items.json");
        let raw: OpenAiResponsesRequest = serde_json::from_str(fixture).unwrap();
        let res = decode_responses_request(raw, "req_codex_fixture");

        assert_eq!(res.fidelity, gateway_ir::Fidelity::Native);
        let req = res.value;
        assert_eq!(req.request_id, "req_codex_fixture");
        assert_eq!(req.model.raw_name(), "coding-smart");
        assert_eq!(req.instructions[0], "You are the Codex Agent executing automated refactoring.");
        assert_eq!(req.tools.len(), 1);
        assert_eq!(req.tools[0].name, "exec");
        assert_eq!(req.tools[0].strict, true);
        assert_eq!(req.items.len(), 3);
    }
}
