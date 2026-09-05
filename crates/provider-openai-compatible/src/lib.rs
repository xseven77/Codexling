pub mod adapter;

pub use adapter::{format_chat_request, parse_stream_chunk};

#[cfg(test)]
mod tests {
    use super::*;
    use gateway_ir::{CanonicalRequest, Message, ModelSelector, ToolDefinition};

    #[test]
    fn test_format_chat_request_payload() {
        let mut req = CanonicalRequest::new("req_egress_1", ModelSelector::alias("coding-fast"));
        req.items.push(gateway_ir::InputItem::from_message(Message::user("Hello DeepSeek")));
        req.tools.push(ToolDefinition::new("read_file", serde_json::json!({"type": "object"})));

        let payload = format_chat_request(&req, "deepseek-chat");
        assert_eq!(payload["model"], "deepseek-chat");
        assert_eq!(payload["messages"][0]["role"], "user");
        assert_eq!(payload["messages"][0]["content"], "Hello DeepSeek");
        assert_eq!(payload["tools"][0]["function"]["name"], "read_file");
    }

    #[test]
    fn test_format_chat_request_payload_with_reasoning_effort() {
        let mut req = CanonicalRequest::new("req_egress_2", ModelSelector::alias("o3-mini"));
        req.items.push(gateway_ir::InputItem::from_message(Message::user("solve")));
        req.generation.reasoning_effort = Some("low".to_string());

        let payload = format_chat_request(&req, "o3-mini");
        assert_eq!(payload["reasoning_effort"], "low");
    }

    #[test]
    fn test_parse_stream_chunk_text_delta() {
        let line = "data: {\"choices\": [{\"delta\": {\"content\": \"fn main() {}\"}}]}";
        let ev = parse_stream_chunk(line, 2, "resp_001", "deepseek-chat").unwrap();

        match ev {
            gateway_stream::StreamEvent::TextDelta(t) => {
                assert_eq!(t.sequence, 2);
                assert_eq!(t.text, "fn main() {}");
            }
            _ => panic!("Expected TextDelta"),
        }
    }

    #[test]
    fn test_parse_stream_chunk_done() {
        let line = "data: [DONE]";
        let ev = parse_stream_chunk(line, 10, "resp_001", "deepseek-chat").unwrap();

        match ev {
            gateway_stream::StreamEvent::ResponseCompleted(rc) => {
                assert_eq!(rc.sequence, 10);
                assert_eq!(rc.finish_reason, gateway_ir::FinishReason::Stop);
            }
            _ => panic!("Expected ResponseCompleted"),
        }
    }
}
