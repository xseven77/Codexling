use gateway_ir::{CanonicalRequest, ContentBlock, InputItem, Role, ToolChoice};
use gateway_stream::event::{
    ResponseCompleted, TextDelta, ToolArgumentsDelta, ToolCallStarted,
};
use gateway_stream::StreamEvent;
use serde_json::json;

/// Formats a CanonicalRequest into an OpenAI-compatible /chat/completions JSON payload.
pub fn format_chat_request(req: &CanonicalRequest, target_model: &str) -> serde_json::Value {
    let mut messages = Vec::new();

    for item in &req.items {
        match item {
            InputItem::Message(m) => {
                let role_str = match m.role {
                    Role::System | Role::Developer => "system",
                    Role::User => "user",
                    Role::Assistant => "assistant",
                    Role::Tool => "tool",
                };

                let mut text_parts = Vec::new();
                let mut tool_calls = Vec::new();

                for block in &m.content {
                    match block {
                        ContentBlock::Text(t) => text_parts.push(t.text.clone()),
                        ContentBlock::ToolCall(tc) => {
                            tool_calls.push(json!({
                                "id": tc.id,
                                "type": "function",
                                "function": {
                                    "name": tc.name,
                                    "arguments": tc.arguments
                                }
                            }));
                        }
                        _ => {}
                    }
                }

                let mut msg_obj = json!({
                    "role": role_str,
                    "content": text_parts.join("")
                });

                if !tool_calls.is_empty() {
                    msg_obj["tool_calls"] = json!(tool_calls);
                }

                messages.push(msg_obj);
            }
            InputItem::ToolResult(tr) => {
                messages.push(json!({
                    "role": "tool",
                    "tool_call_id": tr.call_id,
                    "content": tr.output
                }));
            }
            _ => {}
        }
    }

    let mut payload = json!({
        "model": target_model,
        "messages": messages,
        "stream": req.stream,
    });

    if let Some(t) = req.generation.temperature {
        payload["temperature"] = json!(t);
    }
    if let Some(p) = req.generation.top_p {
        payload["top_p"] = json!(p);
    }
    if let Some(max) = req.generation.max_output_tokens {
        payload["max_tokens"] = json!(max);
    }
    if let Some(ref r) = req.generation.reasoning_effort {
        payload["reasoning_effort"] = json!(r);
    }

    if !req.tools.is_empty() {
        let tools_json: Vec<_> = req
            .tools
            .iter()
            .map(|t| {
                json!({
                    "type": "function",
                    "function": {
                        "name": t.name,
                        "description": t.description,
                        "parameters": t.parameters
                    }
                })
            })
            .collect();
        payload["tools"] = json!(tools_json);
    }

    match &req.tool_choice {
        ToolChoice::None => payload["tool_choice"] = json!("none"),
        ToolChoice::Required => payload["tool_choice"] = json!("required"),
        ToolChoice::Auto => payload["tool_choice"] = json!("auto"),
        ToolChoice::Specific(name) => {
            payload["tool_choice"] = json!({
                "type": "function",
                "function": { "name": name }
            });
        }
    }

    payload
}

/// Parses an upstream OpenAI-compatible SSE chunk line into a Canonical StreamEvent.
pub fn parse_stream_chunk(
    line: &str,
    current_sequence: u64,
    response_id: &str,
    _model: &str,
) -> Option<StreamEvent> {
    let trimmed = line.trim();
    if !trimmed.starts_with("data:") {
        return None;
    }

    let data_part = trimmed.trim_start_matches("data:").trim();
    if data_part == "[DONE]" {
        return Some(StreamEvent::ResponseCompleted(ResponseCompleted {
            sequence: current_sequence,
            finish_reason: gateway_ir::FinishReason::Stop,
        }));
    }

    let parsed: serde_json::Value = serde_json::from_str(data_part).ok()?;
    let choices = parsed.get("choices")?.as_array()?;
    let first_choice = choices.first()?;

    if let Some(finish_str) = first_choice.get("finish_reason").and_then(|f| f.as_str()) {
        let reason = match finish_str {
            "stop" => gateway_ir::FinishReason::Stop,
            "length" => gateway_ir::FinishReason::Length,
            "tool_calls" => gateway_ir::FinishReason::ToolCalls,
            _ => gateway_ir::FinishReason::Stop,
        };
        return Some(StreamEvent::ResponseCompleted(ResponseCompleted {
            sequence: current_sequence,
            finish_reason: reason,
        }));
    }

    let delta = first_choice.get("delta")?;

    if let Some(content) = delta.get("content").and_then(|c| c.as_str()) {
        if !content.is_empty() {
            return Some(StreamEvent::TextDelta(TextDelta {
                sequence: current_sequence,
                item_id: format!("{response_id}_text_0"),
                text: content.to_string(),
            }));
        }
    }

    if let Some(tool_calls) = delta.get("tool_calls").and_then(|t| t.as_array()) {
        if let Some(first_tc) = tool_calls.first() {
            let index = first_tc.get("index").and_then(|i| i.as_u64()).unwrap_or(0) as usize;
            let id = first_tc.get("id").and_then(|id| id.as_str());
            let func = first_tc.get("function");

            if let Some(call_id) = id {
                let name = func
                    .and_then(|f| f.get("name"))
                    .and_then(|n| n.as_str())
                    .unwrap_or_default();
                return Some(StreamEvent::ToolCallStarted(ToolCallStarted {
                    sequence: current_sequence,
                    item_id: format!("{response_id}_call_{index}"),
                    call_id: call_id.to_string(),
                    name: name.to_string(),
                    index,
                }));
            } else if let Some(args_delta) = func
                .and_then(|f| f.get("arguments"))
                .and_then(|a| a.as_str())
            {
                return Some(StreamEvent::ToolArgumentsDelta(ToolArgumentsDelta {
                    sequence: current_sequence,
                    call_id: format!("{response_id}_call_{index}"),
                    delta: args_delta.to_string(),
                }));
            }
        }
    }

    None
}
