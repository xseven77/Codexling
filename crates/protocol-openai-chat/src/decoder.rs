use gateway_ir::{
    CanonicalRequest, ContentBlock, InputItem, Message, ModelSelector, Role,
    ToolCall, ToolChoice, ToolDefinition, ToolResult, TranslationResult,
};
use crate::schema::OpenAiChatRequest;

pub fn decode_chat_request(raw: OpenAiChatRequest, request_id: impl Into<String>) -> TranslationResult<CanonicalRequest> {
    let model = if raw.model.contains('/') {
        let parts: Vec<&str> = raw.model.splitn(2, '/').collect();
        ModelSelector::exact(parts[0], parts[1])
    } else {
        ModelSelector::alias(raw.model)
    };

    let mut canonical = CanonicalRequest::new(request_id, model);
    canonical.stream = raw.stream.unwrap_or(false);

    // Generation hyperparameters
    canonical.generation.temperature = raw.temperature;
    canonical.generation.top_p = raw.top_p;
    canonical.generation.max_output_tokens = raw.max_tokens.or(raw.max_completion_tokens);
    canonical.generation.presence_penalty = raw.presence_penalty;
    canonical.generation.frequency_penalty = raw.frequency_penalty;

    if let Some(stop) = raw.stop {
        match stop {
            serde_json::Value::String(s) => canonical.generation.stop_sequences.push(s),
            serde_json::Value::Array(arr) => {
                for item in arr {
                    if let Some(s) = item.as_str() {
                        canonical.generation.stop_sequences.push(s.to_string());
                    }
                }
            }
            _ => {}
        }
    }

    // Tools
    if let Some(tools) = raw.tools {
        for tool in tools {
            if tool.kind == "function" {
                let mut def = ToolDefinition::new(tool.function.name, tool.function.parameters);
                if let Some(desc) = tool.function.description {
                    def = def.with_description(desc);
                }
                if let Some(strict) = tool.function.strict {
                    def = def.with_strict(strict);
                }
                canonical.tools.push(def);
            }
        }
    }

    // Tool Choice
    if let Some(tc) = raw.tool_choice {
        canonical.tool_choice = match tc {
            serde_json::Value::String(ref s) if s == "none" => ToolChoice::None,
            serde_json::Value::String(ref s) if s == "required" => ToolChoice::Required,
            serde_json::Value::String(ref s) if s == "auto" => ToolChoice::Auto,
            serde_json::Value::Object(ref obj) => {
                if let Some(func) = obj.get("function").and_then(|f| f.get("name")).and_then(|n| n.as_str()) {
                    ToolChoice::Specific(func.to_string())
                } else {
                    ToolChoice::Auto
                }
            }
            _ => ToolChoice::Auto,
        };
    }

    // Messages
    for msg in raw.messages {
        match msg.role.as_str() {
            "system" => {
                let text = extract_content_text(&msg.content);
                canonical.instructions.push(text.clone());
                canonical.items.push(InputItem::from_message(Message::system(text)));
            }
            "developer" => {
                let text = extract_content_text(&msg.content);
                canonical.instructions.push(text.clone());
                canonical.items.push(InputItem::from_message(Message::developer(text)));
            }
            "user" => {
                let text = extract_content_text(&msg.content);
                canonical.items.push(InputItem::from_message(Message::user(text)));
            }
            "assistant" => {
                let mut blocks = Vec::new();
                let text = extract_content_text(&msg.content);
                if !text.is_empty() {
                    blocks.push(ContentBlock::text(text));
                }
                if let Some(calls) = msg.tool_calls {
                    for call in calls {
                        blocks.push(ContentBlock::tool_call(ToolCall::new(
                            call.id,
                            call.function.name,
                            call.function.arguments,
                        )));
                    }
                }
                canonical.items.push(InputItem::from_message(Message::new(Role::Assistant, blocks)));
            }
            "tool" => {
                let text = extract_content_text(&msg.content);
                let call_id = msg.tool_call_id.unwrap_or_default();
                canonical.items.push(InputItem::ToolResult(ToolResult::success(call_id, text)));
            }
            _ => {
                let text = extract_content_text(&msg.content);
                canonical.items.push(InputItem::from_message(Message::user(text)));
            }
        }
    }

    TranslationResult::native(canonical)
}

fn extract_content_text(content: &Option<serde_json::Value>) -> String {
    match content {
        Some(serde_json::Value::String(s)) => s.clone(),
        Some(serde_json::Value::Array(arr)) => {
            let mut buf = String::new();
            for item in arr {
                if let Some(obj) = item.as_object() {
                    if obj.get("type").and_then(|t| t.as_str()) == Some("text") {
                        if let Some(text) = obj.get("text").and_then(|t| t.as_str()) {
                            buf.push_str(text);
                        }
                    }
                }
            }
            buf
        }
        _ => String::new(),
    }
}
