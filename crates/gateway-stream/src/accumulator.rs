use std::collections::BTreeMap;
use gateway_ir::{
    CanonicalResponse, ContentBlock, FinishReason, ReasoningBlock, TextBlock, ToolCall, Usage,
};
use crate::event::StreamEvent;
use thiserror::Error;

#[derive(Debug, Error, PartialEq)]
pub enum AccumulatorError {
    #[error("Stream started more than once")]
    DuplicateStart,
    #[error("Event received before stream was started")]
    NotStarted,
    #[error("Non-monotonic sequence: expected > {expected}, got {received}")]
    SequenceOutdated { expected: u64, received: u64 },
    #[error("Terminal event received multiple times")]
    AlreadyTerminated,
    #[error("Stream finished without terminal event")]
    Unterminated,
    #[error("Tool call {0} delta received without ToolCallStarted")]
    UnknownToolCall(String),
}

/// Accumulates a stream of canonical StreamEvents into a complete CanonicalResponse.
#[derive(Debug, Default)]
pub struct StreamAccumulator {
    response_id: Option<String>,
    model: Option<String>,
    last_sequence: u64,
    is_started: bool,
    is_terminated: bool,
    finish_reason: Option<FinishReason>,
    usage: Option<Usage>,

    // In-flight items
    // item_id -> text content
    text_items: BTreeMap<String, String>,
    // item_id -> (reasoning text, optional signature)
    reasoning_items: BTreeMap<String, (String, Option<String>)>,
    // call_id -> (item_id, name, accumulated arguments)
    tool_calls: BTreeMap<String, (String, String, String)>,
    // Order of items: list of (item_type, key)
    ordered_items: Vec<(ItemKind, String)>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum ItemKind {
    Text,
    Reasoning,
    ToolCall,
}

impl StreamAccumulator {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn process(&mut self, event: &StreamEvent) -> Result<(), AccumulatorError> {
        if let Some(seq) = event.sequence() {
            if seq <= self.last_sequence && self.last_sequence > 0 {
                return Err(AccumulatorError::SequenceOutdated {
                    expected: self.last_sequence,
                    received: seq,
                });
            }
            self.last_sequence = seq;
        }

        match event {
            StreamEvent::ResponseStarted(e) => {
                if self.is_started {
                    return Err(AccumulatorError::DuplicateStart);
                }
                self.is_started = true;
                self.response_id = Some(e.response_id.clone());
                self.model = Some(e.model.clone());
            }
            StreamEvent::ItemStarted(_) => {
                self.ensure_started()?;
                // Placeholder ready to be specialized by the first delta
            }
            StreamEvent::TextDelta(e) => {
                self.ensure_started()?;
                self.ensure_not_terminated()?;
                if !self.text_items.contains_key(&e.item_id) {
                    self.ordered_items.push((ItemKind::Text, e.item_id.clone()));
                }
                self.text_items
                    .entry(e.item_id.clone())
                    .or_default()
                    .push_str(&e.text);
            }
            StreamEvent::ReasoningDelta(e) => {
                self.ensure_started()?;
                self.ensure_not_terminated()?;
                if !self.reasoning_items.contains_key(&e.item_id) {
                    self.ordered_items.push((ItemKind::Reasoning, e.item_id.clone()));
                }
                let entry = self
                    .reasoning_items
                    .entry(e.item_id.clone())
                    .or_insert_with(|| (String::new(), None));
                entry.0.push_str(&e.text);
                if let Some(sig) = &e.signature {
                    entry.1 = Some(sig.clone());
                }
            }
            StreamEvent::ToolCallStarted(e) => {
                self.ensure_started()?;
                self.ensure_not_terminated()?;
                self.ordered_items.push((ItemKind::ToolCall, e.call_id.clone()));
                self.tool_calls.insert(
                    e.call_id.clone(),
                    (e.item_id.clone(), e.name.clone(), String::new()),
                );
            }
            StreamEvent::ToolArgumentsDelta(e) => {
                self.ensure_started()?;
                self.ensure_not_terminated()?;
                let call = self
                    .tool_calls
                    .get_mut(&e.call_id)
                    .ok_or_else(|| AccumulatorError::UnknownToolCall(e.call_id.clone()))?;
                call.2.push_str(&e.delta);
            }
            StreamEvent::ToolCallCompleted(e) => {
                self.ensure_started()?;
                self.ensure_not_terminated()?;
                let call = self
                    .tool_calls
                    .get_mut(&e.call_id)
                    .ok_or_else(|| AccumulatorError::UnknownToolCall(e.call_id.clone()))?;
                // If the delta already accumulated arguments, ensure it matches or overwrite
                if call.2.is_empty() {
                    call.2 = e.arguments.clone();
                }
            }
            StreamEvent::ItemCompleted(_) => {
                self.ensure_started()?;
            }
            StreamEvent::UsageUpdated(usage) => {
                self.usage = Some(*usage);
            }
            StreamEvent::ResponseCompleted(e) => {
                self.ensure_started()?;
                if self.is_terminated {
                    return Err(AccumulatorError::AlreadyTerminated);
                }
                self.is_terminated = true;
                self.finish_reason = Some(e.finish_reason);
            }
            StreamEvent::ResponseFailed(_) => {
                if self.is_terminated {
                    return Err(AccumulatorError::AlreadyTerminated);
                }
                self.is_terminated = true;
                self.finish_reason = Some(FinishReason::Error);
            }
            StreamEvent::KeepAlive => {}
        }

        Ok(())
    }

    pub fn finish(self) -> Result<CanonicalResponse, AccumulatorError> {
        if !self.is_terminated {
            return Err(AccumulatorError::Unterminated);
        }

        let mut items = Vec::new();
        for (kind, id) in self.ordered_items {
            match kind {
                ItemKind::Text => {
                    if let Some(text) = self.text_items.get(&id) {
                        items.push(ContentBlock::Text(TextBlock::new(text)));
                    }
                }
                ItemKind::Reasoning => {
                    if let Some((text, sig)) = self.reasoning_items.get(&id) {
                        let mut block = ReasoningBlock::new(text);
                        if let Some(s) = sig {
                            block = block.with_signature(s);
                        }
                        items.push(ContentBlock::Reasoning(block));
                    }
                }
                ItemKind::ToolCall => {
                    if let Some((_, name, args)) = self.tool_calls.get(&id) {
                        items.push(ContentBlock::ToolCall(ToolCall::new(
                            id,
                            name.clone(),
                            args.clone(),
                        )));
                    }
                }
            }
        }

        Ok(CanonicalResponse {
            response_id: self.response_id.unwrap_or_else(|| "resp_stream".into()),
            model: self.model.unwrap_or_default(),
            items,
            finish_reason: self.finish_reason.unwrap_or(FinishReason::Stop),
            usage: self.usage,
            provider_state: Vec::new(),
        })
    }

    fn ensure_started(&self) -> Result<(), AccumulatorError> {
        if !self.is_started {
            Err(AccumulatorError::NotStarted)
        } else {
            Ok(())
        }
    }

    fn ensure_not_terminated(&self) -> Result<(), AccumulatorError> {
        if self.is_terminated {
            Err(AccumulatorError::AlreadyTerminated)
        } else {
            Ok(())
        }
    }
}
