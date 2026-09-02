use gateway_stream::StreamEvent;

pub fn encode_anthropic_stream_event(
    event: &StreamEvent,
    response_id: &str,
    model: &str,
) -> Vec<String> {
    let mut lines = Vec::new();

    match event {
        StreamEvent::ResponseStarted(_) => {
            let start_payload = serde_json::json!({
                "type": "message_start",
                "message": {
                    "id": response_id,
                    "type": "message",
                    "role": "assistant",
                    "model": model,
                    "content": [],
                    "stop_reason": null,
                    "usage": {
                        "input_tokens": 10,
                        "output_tokens": 0
                    }
                }
            });
            lines.push(format!("event: message_start\ndata: {start_payload}\n\n"));

            let block_start = serde_json::json!({
                "type": "content_block_start",
                "index": 0,
                "content_block": {
                    "type": "text",
                    "text": ""
                }
            });
            lines.push(format!("event: content_block_start\ndata: {block_start}\n\n"));
        }
        StreamEvent::TextDelta(t) => {
            let delta_payload = serde_json::json!({
                "type": "content_block_delta",
                "index": 0,
                "delta": {
                    "type": "text_delta",
                    "text": t.text
                }
            });
            lines.push(format!("event: content_block_delta\ndata: {delta_payload}\n\n"));
        }
        StreamEvent::ToolCallStarted(tc) => {
            let block_start = serde_json::json!({
                "type": "content_block_start",
                "index": tc.index,
                "content_block": {
                    "type": "tool_use",
                    "id": tc.call_id,
                    "name": tc.name,
                    "input": {}
                }
            });
            lines.push(format!("event: content_block_start\ndata: {block_start}\n\n"));
        }
        StreamEvent::ToolArgumentsDelta(args) => {
            let delta_payload = serde_json::json!({
                "type": "content_block_delta",
                "index": 0,
                "delta": {
                    "type": "input_json_delta",
                    "partial_json": args.delta
                }
            });
            lines.push(format!("event: content_block_delta\ndata: {delta_payload}\n\n"));
        }
        StreamEvent::ToolCallCompleted(_) => {
            let stop_payload = serde_json::json!({
                "type": "content_block_stop",
                "index": 0
            });
            lines.push(format!("event: content_block_stop\ndata: {stop_payload}\n\n"));
        }
        StreamEvent::ResponseCompleted(rc) => {
            let block_stop = serde_json::json!({
                "type": "content_block_stop",
                "index": 0
            });
            lines.push(format!("event: content_block_stop\ndata: {block_stop}\n\n"));

            let stop_reason = match rc.finish_reason {
                gateway_ir::FinishReason::Stop => "end_turn",
                gateway_ir::FinishReason::Length => "max_tokens",
                gateway_ir::FinishReason::ToolCalls => "tool_use",
                _ => "end_turn",
            };

            let delta_payload = serde_json::json!({
                "type": "message_delta",
                "delta": {
                    "stop_reason": stop_reason,
                    "stop_sequence": null
                },
                "usage": {
                    "output_tokens": 15
                }
            });
            lines.push(format!("event: message_delta\ndata: {delta_payload}\n\n"));

            let msg_stop = serde_json::json!({
                "type": "message_stop"
            });
            lines.push(format!("event: message_stop\ndata: {msg_stop}\n\n"));
        }
        _ => {}
    }

    lines
}
