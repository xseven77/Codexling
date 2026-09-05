use gateway_ir::{
    CanonicalRequest, ContentBlock, InputItem, Message, ModelSelector, Role, ToolCall,
    ToolDefinition, ToolResult, TranslationResult,
};
use crate::schema::AnthropicMessagesRequest;

pub fn decode_anthropic_request(
    raw: AnthropicMessagesRequest,
    request_id: impl Into<String>,
) -> TranslationResult<CanonicalRequest> {
    let model = if raw.model.contains('/') {
        let parts: Vec<&str> = raw.model.splitn(2, '/').collect();
        ModelSelector::exact(parts[0], parts[1])
    } else {
        ModelSelector::alias(raw.model)
    };

    let mut canonical = CanonicalRequest::new(request_id, model);
    canonical.stream = raw.stream.unwrap_or(false);
    canonical.generation.max_output_tokens = Some(raw.max_tokens);
    canonical.generation.temperature = raw.temperature;
    canonical.generation.top_p = raw.top_p;

    if let Some(stops) = raw.stop_sequences {
        canonical.generation.stop_sequences = stops;
    }

    if let Some(th) = raw.thinking {
        if let Some(obj) = th.as_object() {
            if obj.get("type").and_then(|t| t.as_str()) == Some("disabled") {
                canonical.generation.reasoning_effort = Some("none".into());
            } else if let Some(budget) = obj.get("budget_tokens").and_then(|b| b.as_u64()) {
                canonical.generation.reasoning_effort = Some(budget.to_string());
            } else {
                canonical.generation.reasoning_effort = Some("medium".into());
            }
        }
    }

    // System instructions
    if let Some(sys) = raw.system {
        match sys {
            serde_json::Value::String(s) => canonical.instructions.push(s),
            serde_json::Value::Array(arr) => {
                for item in arr {
                    if let Some(text) = item.get("text").and_then(|t| t.as_str()) {
                        canonical.instructions.push(text.to_string());
                    }
                }
            }
            _ => {}
        }
    }

    // Tools
    if let Some(tools) = raw.tools {
        for t in tools {
            let mut def = ToolDefinition::new(t.name, t.input_schema);
            if let Some(desc) = t.description {
                def = def.with_description(desc);
            }
            canonical.tools.push(def);
        }
    }

    // Messages
    for msg in raw.messages {
        let role = match msg.role.as_str() {
            "assistant" => Role::Assistant,
            _ => Role::User,
        };

        match msg.content {
            serde_json::Value::String(s) => {
                canonical.items.push(InputItem::from_message(Message::new(
                    role,
                    vec![ContentBlock::text(s)],
                )));
            }
            serde_json::Value::Array(arr) => {
                let mut blocks = Vec::new();
                for block in arr {
                    let block_type = block.get("type").and_then(|t| t.as_str()).unwrap_or_default();
                    match block_type {
                        "text" => {
                            if let Some(text) = block.get("text").and_then(|t| t.as_str()) {
                                blocks.push(ContentBlock::text(text));
                            }
                        }
                        "tool_use" => {
                            let id = block.get("id").and_then(|i| i.as_str()).unwrap_or_default();
                            let name = block.get("name").and_then(|n| n.as_str()).unwrap_or_default();
                            let input = block.get("input").unwrap_or(&serde_json::Value::Null);
                            let args_str = serde_json::to_string(input).unwrap_or_default();
                            blocks.push(ContentBlock::tool_call(ToolCall::new(id, name, args_str)));
                        }
                        "tool_result" => {
                            let call_id = block.get("tool_use_id").and_then(|i| i.as_str()).unwrap_or_default();
                            let content_text = match block.get("content") {
                                Some(serde_json::Value::String(s)) => s.clone(),
                                Some(other) => serde_json::to_string(other).unwrap_or_default(),
                                None => String::new(),
                            };
                            canonical.items.push(InputItem::ToolResult(ToolResult::success(call_id, content_text)));
                        }
                        _ => {}
                    }
                }

                if !blocks.is_empty() {
                    canonical.items.push(InputItem::from_message(Message::new(role, blocks)));
                }
            }
            _ => {}
        }
    }

    TranslationResult::native(canonical)
}
