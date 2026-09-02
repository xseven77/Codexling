use gateway_ir::{CanonicalResponse, ContentBlock, FinishReason};
use gateway_stream::StreamEvent;
use crate::schema::{
    OpenAiChatChoice, OpenAiChatChunk, OpenAiChatResponse, OpenAiChunkChoice, OpenAiChunkDelta,
    OpenAiChunkFunctionCall, OpenAiChunkToolCall, OpenAiFunctionCall, OpenAiResponseMessage,
    OpenAiToolCall, OpenAiUsage,
};

pub fn encode_chat_response(resp: &CanonicalResponse, created: u64) -> OpenAiChatResponse {
    let mut text_parts = Vec::new();
    let mut tool_calls = Vec::new();

    for item in &resp.items {
        match item {
            ContentBlock::Text(t) => text_parts.push(t.text.clone()),
            ContentBlock::Reasoning(_r) => {
                // If reasoning is present in non-streaming, append or keep
            }
            ContentBlock::ToolCall(tc) => {
                tool_calls.push(OpenAiToolCall {
                    id: tc.id.clone(),
                    kind: "function".into(),
                    function: OpenAiFunctionCall {
                        name: tc.name.clone(),
                        arguments: tc.arguments.clone(),
                    },
                });
            }
            _ => {}
        }
    }

    let finish_reason = match resp.finish_reason {
        FinishReason::Stop => "stop",
        FinishReason::Length => "length",
        FinishReason::ToolCalls => "tool_calls",
        FinishReason::ContentFilter => "content_filter",
        FinishReason::Error => "error",
    };

    let content = if text_parts.is_empty() {
        None
    } else {
        Some(text_parts.join(""))
    };

    let message = OpenAiResponseMessage {
        role: "assistant".into(),
        content,
        tool_calls: if tool_calls.is_empty() { None } else { Some(tool_calls) },
    };

    let usage = resp.usage.map(|u| OpenAiUsage {
        prompt_tokens: u.input_tokens,
        completion_tokens: u.output_tokens,
        total_tokens: u.input_tokens + u.output_tokens,
    });

    OpenAiChatResponse {
        id: resp.response_id.clone(),
        object: "chat.completion".into(),
        created,
        model: resp.model.clone(),
        choices: vec![OpenAiChatChoice {
            index: 0,
            message,
            finish_reason: finish_reason.into(),
        }],
        usage,
    }
}

/// Convert a StreamEvent into OpenAI chat completion SSE string chunks.
pub fn encode_chat_stream_event(
    event: &StreamEvent,
    response_id: &str,
    model: &str,
    created: u64,
) -> Vec<String> {
    let mut lines = Vec::new();

    match event {
        StreamEvent::ResponseStarted(_) => {
            // Initial chunk containing role: assistant
            let chunk = OpenAiChatChunk {
                id: response_id.to_string(),
                object: "chat.completion.chunk".into(),
                created,
                model: model.to_string(),
                choices: vec![OpenAiChunkChoice {
                    index: 0,
                    delta: OpenAiChunkDelta {
                        role: Some("assistant".into()),
                        content: Some("".into()),
                        tool_calls: None,
                    },
                    finish_reason: None,
                }],
                usage: None,
            };
            if let Ok(json) = serde_json::to_string(&chunk) {
                lines.push(format!("data: {json}\n\n"));
            }
        }
        StreamEvent::TextDelta(t) => {
            let chunk = OpenAiChatChunk {
                id: response_id.to_string(),
                object: "chat.completion.chunk".into(),
                created,
                model: model.to_string(),
                choices: vec![OpenAiChunkChoice {
                    index: 0,
                    delta: OpenAiChunkDelta {
                        role: None,
                        content: Some(t.text.clone()),
                        tool_calls: None,
                    },
                    finish_reason: None,
                }],
                usage: None,
            };
            if let Ok(json) = serde_json::to_string(&chunk) {
                lines.push(format!("data: {json}\n\n"));
            }
        }
        StreamEvent::ToolCallStarted(tc) => {
            let chunk = OpenAiChatChunk {
                id: response_id.to_string(),
                object: "chat.completion.chunk".into(),
                created,
                model: model.to_string(),
                choices: vec![OpenAiChunkChoice {
                    index: 0,
                    delta: OpenAiChunkDelta {
                        role: None,
                        content: None,
                        tool_calls: Some(vec![OpenAiChunkToolCall {
                            index: tc.index,
                            id: Some(tc.call_id.clone()),
                            kind: Some("function".into()),
                            function: OpenAiChunkFunctionCall {
                                name: Some(tc.name.clone()),
                                arguments: Some("".into()),
                            },
                        }]),
                    },
                    finish_reason: None,
                }],
                usage: None,
            };
            if let Ok(json) = serde_json::to_string(&chunk) {
                lines.push(format!("data: {json}\n\n"));
            }
        }
        StreamEvent::ToolArgumentsDelta(args) => {
            let chunk = OpenAiChatChunk {
                id: response_id.to_string(),
                object: "chat.completion.chunk".into(),
                created,
                model: model.to_string(),
                choices: vec![OpenAiChunkChoice {
                    index: 0,
                    delta: OpenAiChunkDelta {
                        role: None,
                        content: None,
                        tool_calls: Some(vec![OpenAiChunkToolCall {
                            index: 0,
                            id: Some(args.call_id.clone()),
                            kind: None,
                            function: OpenAiChunkFunctionCall {
                                name: None,
                                arguments: Some(args.delta.clone()),
                            },
                        }]),
                    },
                    finish_reason: None,
                }],
                usage: None,
            };
            if let Ok(json) = serde_json::to_string(&chunk) {
                lines.push(format!("data: {json}\n\n"));
            }
        }
        StreamEvent::ResponseCompleted(rc) => {
            let finish = match rc.finish_reason {
                FinishReason::Stop => "stop",
                FinishReason::Length => "length",
                FinishReason::ToolCalls => "tool_calls",
                FinishReason::ContentFilter => "content_filter",
                FinishReason::Error => "error",
            };
            let chunk = OpenAiChatChunk {
                id: response_id.to_string(),
                object: "chat.completion.chunk".into(),
                created,
                model: model.to_string(),
                choices: vec![OpenAiChunkChoice {
                    index: 0,
                    delta: OpenAiChunkDelta::default(),
                    finish_reason: Some(finish.into()),
                }],
                usage: None,
            };
            if let Ok(json) = serde_json::to_string(&chunk) {
                lines.push(format!("data: {json}\n\n"));
            }
            lines.push("data: [DONE]\n\n".to_string());
        }
        StreamEvent::ResponseFailed(err) => {
            lines.push(format!(
                "event: error\ndata: {}\n\n",
                serde_json::json!({ "error": { "message": err.message, "code": err.code } })
            ));
        }
        _ => {}
    }

    lines
}
