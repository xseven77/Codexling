pub mod decoder;
pub mod encoder;
pub mod schema;

pub use decoder::decode_chat_request;
pub use encoder::{encode_chat_response, encode_chat_stream_event};
pub use schema::{OpenAiChatRequest, OpenAiChatResponse, OpenAiChatChunk};

#[cfg(test)]
mod tests {
    use super::*;
    use gateway_ir::{ContentBlock, FinishReason, InputItem, Role, ToolChoice};
    use gateway_stream::event::{ResponseCompleted, ResponseStarted, TextDelta};
    use gateway_stream::StreamEvent;

    #[test]
    fn test_decode_chat_request_with_tools_and_messages() {
        let json = r#"{
            "model": "coding-fast",
            "messages": [
                {"role": "system", "content": "You are a helpful coding assistant."},
                {"role": "user", "content": "Write a test"},
                {"role": "assistant", "content": null, "tool_calls": [
                    {
                        "id": "call_123",
                        "type": "function",
                        "function": {
                            "name": "read_file",
                            "arguments": "{\"path\":\"Cargo.toml\"}"
                        }
                    }
                ]},
                {"role": "tool", "tool_call_id": "call_123", "content": "[package]\nname = \"test\""}
            ],
            "tools": [
                {
                    "type": "function",
                    "function": {
                        "name": "read_file",
                        "description": "Read file contents",
                        "parameters": {"type": "object", "properties": {"path": {"type": "string"}}}
                    }
                }
            ],
            "tool_choice": "auto",
            "temperature": 0.2,
            "stream": true
        }"#;

        let raw: OpenAiChatRequest = serde_json::from_str(json).unwrap();
        let res = decode_chat_request(raw, "req_chat_test");

        assert_eq!(res.fidelity, gateway_ir::Fidelity::Native);
        let req = res.value;
        assert_eq!(req.request_id, "req_chat_test");
        assert_eq!(req.model.raw_name(), "coding-fast");
        assert_eq!(req.stream, true);
        assert_eq!(req.generation.temperature, Some(0.2));
        assert_eq!(req.tool_choice, ToolChoice::Auto);
        assert_eq!(req.tools.len(), 1);
        assert_eq!(req.tools[0].name, "read_file");

        // Verify items: system, user, assistant with tool call, tool result
        assert_eq!(req.items.len(), 4);
        match &req.items[2] {
            InputItem::Message(m) => {
                assert_eq!(m.role, Role::Assistant);
                match &m.content[0] {
                    ContentBlock::ToolCall(tc) => {
                        assert_eq!(tc.id, "call_123");
                        assert_eq!(tc.name, "read_file");
                        assert_eq!(tc.arguments, "{\"path\":\"Cargo.toml\"}");
                    }
                    _ => panic!("Expected tool call block"),
                }
            }
            _ => panic!("Expected message item"),
        }

        match &req.items[3] {
            InputItem::ToolResult(tr) => {
                assert_eq!(tr.call_id, "call_123");
                assert!(tr.output.contains("[package]"));
            }
            _ => panic!("Expected tool result item"),
        }
    }

    #[test]
    fn test_encode_chat_stream_events() {
        let ev1 = StreamEvent::ResponseStarted(ResponseStarted {
            sequence: 1,
            response_id: "resp_1".into(),
            model: "coding-fast".into(),
            created_at: 1724900000,
        });
        let lines1 = encode_chat_stream_event(&ev1, "resp_1", "coding-fast", 1724900000);
        assert_eq!(lines1.len(), 1);
        assert!(lines1[0].contains("\"role\":\"assistant\""));

        let ev2 = StreamEvent::TextDelta(TextDelta {
            sequence: 2,
            item_id: "m1".into(),
            text: "Hello".into(),
        });
        let lines2 = encode_chat_stream_event(&ev2, "resp_1", "coding-fast", 1724900000);
        assert_eq!(lines2.len(), 1);
        assert!(lines2[0].contains("\"content\":\"Hello\""));

        let ev3 = StreamEvent::ResponseCompleted(ResponseCompleted {
            sequence: 3,
            finish_reason: FinishReason::Stop,
        });
        let lines3 = encode_chat_stream_event(&ev3, "resp_1", "coding-fast", 1724900000);
        assert_eq!(lines3.len(), 2);
        assert!(lines3[0].contains("\"finish_reason\":\"stop\""));
        assert_eq!(lines3[1], "data: [DONE]\n\n");
    }

    #[test]
    fn test_fixture_request_parallel_tools() {
        let fixture = include_str!("../../../fixtures/protocols/openai-chat/request_parallel_tools.json");
        let raw: OpenAiChatRequest = serde_json::from_str(fixture).unwrap();
        let res = decode_chat_request(raw, "req_parallel_fixture");

        assert_eq!(res.fidelity, gateway_ir::Fidelity::Native);
        let req = res.value;
        assert_eq!(req.request_id, "req_parallel_fixture");
        assert_eq!(req.model.raw_name(), "coding-smart");
        assert_eq!(req.stream, true);
        assert_eq!(req.tools.len(), 2);
        assert_eq!(req.tools[0].name, "view_file");
        assert_eq!(req.tools[0].strict, true);
        assert_eq!(req.tools[1].name, "run_command");
        assert_eq!(req.items.len(), 5);
    }
}
