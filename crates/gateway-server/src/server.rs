use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Arc;

use gateway_ir::{Capability, CapabilitySet, FinishReason};
use gateway_routing::{ModelAliasDefinition, RouteCandidate, RouteTable};
use gateway_stream::event::{ResponseCompleted, ResponseStarted, TextDelta};
use gateway_stream::StreamEvent;
use protocol_anthropic_messages::{
    decode_anthropic_request, encode_anthropic_stream_event, AnthropicMessagesRequest,
};
use protocol_openai_chat::{decode_chat_request, encode_chat_stream_event, OpenAiChatRequest};
use protocol_openai_responses::{
    decode_responses_request, encode_responses_stream_event, OpenAiResponsesRequest,
};

use std::collections::{HashMap, VecDeque};
use std::sync::Mutex;

#[derive(Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GatewayRequestRecord {
    pub id: String,
    pub time: String,
    pub agent: String,
    pub ingress_protocol: String,
    pub model_alias: String,
    pub target_provider: String,
    pub target_model: String,
    pub latency_ms: u64,
    pub ttft_ms: u64,
    pub tokens: usize,
    pub fidelity: String,
    pub status: String,
}

#[cfg(test)]
mod tests {
    use super::GatewayServer;
    use std::fs;
    use std::sync::atomic::{AtomicUsize, Ordering};

    static NEXT_TEMP_HOME: AtomicUsize = AtomicUsize::new(0);

    fn temporary_home() -> std::path::PathBuf {
        std::env::temp_dir().join(format!(
            "codexling-gateway-models-{}-{}-{}",
            std::process::id(),
            NEXT_TEMP_HOME.fetch_add(1, Ordering::Relaxed),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ))
    }

    #[test]
    fn model_catalog_uses_wire_safe_ids_and_excludes_disabled_accounts() {
        let home = temporary_home();
        let support = home.join("Library/Application Support/Codexling");
        fs::create_dir_all(&support).unwrap();
        fs::write(
            support.join("connections-v1.json"),
            r#"{
                "codexAccounts": [
                    {"label":"Seven X","isEnabled":true,"authenticationState":"connected","availableModelIDs":["gpt-5.6-wm"]},
                    {"label":"Disabled User","isEnabled":false,"availableModelIDs":["disabled-model"]}
                ],
                "geminiConnections": [],
                "deepSeekConnections": [],
                "openCodeConnections": []
            }"#,
        )
        .unwrap();

        let payload = GatewayServer::get_dynamic_models_payload_for_home(home.to_str().unwrap());
        let models = payload["data"].as_array().unwrap();
        assert!(!models.is_empty());
        assert_eq!(models[0]["id"], "openai/gpt-5.6@Seven-X");
        assert!(models.iter().all(|model| {
            model["id"]
                .as_str()
                .is_some_and(|id| !id.chars().any(char::is_whitespace))
        }));
        assert!(models
            .iter()
            .all(|model| model["account"] != "Disabled User"));

        fs::remove_dir_all(home).unwrap();
    }

    #[test]
    fn model_catalog_has_no_fabricated_fallback_when_every_account_is_disabled() {
        let home = temporary_home();
        let support = home.join("Library/Application Support/Codexling");
        fs::create_dir_all(&support).unwrap();
        fs::write(
            support.join("connections-v1.json"),
            r#"{
                "codexAccounts": [{"label":"Disabled User","isEnabled":false}],
                "geminiConnections": [],
                "deepSeekConnections": [],
                "openCodeConnections": []
            }"#,
        )
        .unwrap();

        let payload = GatewayServer::get_dynamic_models_payload_for_home(home.to_str().unwrap());
        assert!(payload["data"].as_array().unwrap().is_empty());

        fs::remove_dir_all(home).unwrap();
    }

    #[test]
    fn model_catalog_exports_enabled_gemini_oauth_accounts() {
        let home = temporary_home();
        let support = home.join("Library/Application Support/Codexling");
        fs::create_dir_all(support.join("gemini_oauth")).unwrap();
        fs::write(
            support.join("connections-v1.json"),
            r#"{
                "codexAccounts": [],
                "geminiConnections": [{
                    "label":"OAuth User",
                    "credentialHandle":"oauth-handle",
                    "isEnabled":true,
                    "authenticationState":"connected",
                    "availableModelIDs":["gemini-3.6-flash"]
                }],
                "deepSeekConnections": [],
                "openCodeConnections": []
            }"#,
        )
        .unwrap();
        fs::write(
            support.join("gemini_oauth/oauth-handle.json"),
            r#"{"accessToken":"oauth-access-token","refreshToken":"oauth-refresh-token"}"#,
        )
        .unwrap();

        let payload = GatewayServer::get_dynamic_models_payload_for_home(home.to_str().unwrap());
        let models = payload["data"].as_array().unwrap();
        assert!(models.iter().any(|model| {
            model["id"] == "google/gemini-3.6-flash@OAuth-User"
                && model["provider"] == "Google Gemini"
        }));

        fs::remove_dir_all(home).unwrap();
    }

    #[test]
    fn cloud_code_payload_wraps_native_generation_request() {
        let native_request = serde_json::json!({
            "contents": [{"role": "user", "parts": [{"text": "OAuth OK"}]}]
        });
        let payload = GatewayServer::cloud_code_generate_payload(
            "cloud-code-project",
            "gemini-2.5-flash",
            native_request.clone(),
            "codexling-test",
        );

        assert_eq!(payload["project"], "cloud-code-project");
        assert_eq!(payload["model"], "gemini-2.5-flash");
        assert_eq!(payload["request"], native_request);
        assert_eq!(payload["requestId"], "codexling-test");
    }

    #[test]
    fn cloud_code_response_unwraps_generated_text() {
        let response = serde_json::json!({
            "response": {
                "candidates": [{
                    "content": {"parts": [{"text": "first"}, {"text": "second"}]}
                }]
            }
        });

        assert_eq!(
            GatewayServer::cloud_code_response_text(&response).as_deref(),
            Some("first\nsecond")
        );
    }

    #[test]
    fn cloud_code_tools_round_trip_to_openai_shape() {
        let request = serde_json::json!({
            "tools": [{"type":"function", "function": {
                "name":"read_file", "description":"Read a file",
                "parameters":{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}
            }}],
            "tool_choice": "required"
        });
        let tools = GatewayServer::openai_tools_to_gemini(&request).unwrap();
        assert_eq!(tools[0]["functionDeclarations"][0]["name"], "read_file");
        assert_eq!(
            GatewayServer::openai_tool_choice_to_gemini(request.get("tool_choice")).unwrap()
                ["functionCallingConfig"]["mode"],
            "ANY"
        );

        let response = serde_json::json!({"response":{"candidates":[{"content":{"parts":[{
            "functionCall":{"name":"read_file","args":{"path":"README.md"}}
        }]}}]}});
        let message = GatewayServer::new("test-token")
            .cloud_code_response_message(&response)
            .unwrap();
        assert_eq!(message["tool_calls"][0]["function"]["name"], "read_file");
        assert_eq!(
            message["tool_calls"][0]["function"]["arguments"],
            "{\"path\":\"README.md\"}"
        );
    }

    #[test]
    fn parses_swift_oauth_expiry_dates() {
        assert_eq!(
            GatewayServer::parse_rfc3339_utc("1970-01-01T00:00:00Z"),
            Some(0)
        );
        assert_eq!(
            GatewayServer::parse_rfc3339_utc("1970-01-02T00:00:00.000Z"),
            Some(86_400)
        );
        assert_eq!(GatewayServer::parse_rfc3339_utc("not-a-date"), None);
    }

    #[test]
    fn matches_gateway_account_slug_against_email() {
        assert!(GatewayServer::gateway_account_filter_matches(
            "xujinqixujinqi-gmail-com",
            &["", "xujinqixujinqi@gmail.com", "xujinqixujinqi@gmail.com"],
        ));
        assert!(!GatewayServer::gateway_account_filter_matches(
            "another-account",
            &["", "xujinqixujinqi@gmail.com", "xujinqixujinqi@gmail.com"],
        ));
    }
}

pub struct UpstreamEndpoint {
    pub url: String,
    pub auth_header: String,
    pub extra_headers: Vec<(String, String)>,
    pub project: Option<String>,
    pub target_model: String,
    pub provider_name: String,
    pub _account_name: String,
    /// ChatGPT/Codex subscriptions use the local Codex runtime rather than the
    /// public OpenAI API-key endpoint. `None` means a normal HTTP upstream.
    pub codex_home: Option<String>,
}

pub struct GatewayServer {
    pub token: String,
    pub route_table: RouteTable,
    pub active_requests: Arc<AtomicUsize>,
    pub total_requests: Arc<AtomicUsize>,
    pub total_input_tokens: Arc<AtomicUsize>,
    pub total_output_tokens: Arc<AtomicUsize>,
    pub total_tool_calls: Arc<AtomicUsize>,
    pub is_running: Arc<AtomicBool>,
    pub recent_requests: Arc<Mutex<VecDeque<GatewayRequestRecord>>>,
    /// Hermes keeps standard OpenAI tool-call IDs but may discard vendor
    /// extension fields. Cache Gemini's required thought signatures by ID so
    /// a subsequent tool result can be replayed correctly.
    pub gemini_thought_signatures: Arc<Mutex<HashMap<String, String>>>,
}

impl GatewayServer {
    pub fn new(token: impl Into<String>) -> Self {
        let mut route_table = RouteTable::new();

        // 1. Direct Bridge: Gemini Models (Backed by Google session)
        let mut gemini_pro = ModelAliasDefinition::new("gemini-2.5-pro");
        gemini_pro = gemini_pro
            .add_candidate(RouteCandidate::new("gemini", "gemini-2.5-pro").with_priority(100));
        route_table.register_alias(gemini_pro);

        let mut gemini_flash25 = ModelAliasDefinition::new("gemini-2.5-flash");
        gemini_flash25 = gemini_flash25
            .add_candidate(RouteCandidate::new("gemini", "gemini-2.5-flash").with_priority(100));
        route_table.register_alias(gemini_flash25);

        let mut gemini_flash = ModelAliasDefinition::new("gemini-2.0-flash");
        gemini_flash = gemini_flash
            .add_candidate(RouteCandidate::new("gemini", "gemini-2.0-flash").with_priority(100));
        route_table.register_alias(gemini_flash);

        // 2. Direct Bridge: DeepSeek Models (Backed by DeepSeek account)
        let mut ds_chat = ModelAliasDefinition::new("deepseek-chat");
        ds_chat = ds_chat
            .add_candidate(RouteCandidate::new("deepseek", "deepseek-chat").with_priority(100));
        route_table.register_alias(ds_chat);

        let mut ds_reasoner = ModelAliasDefinition::new("deepseek-reasoner");
        ds_reasoner = ds_reasoner
            .add_candidate(RouteCandidate::new("deepseek", "deepseek-reasoner").with_priority(100));
        route_table.register_alias(ds_reasoner);

        // 3. Compatibility & Fallback Mappings
        let mut claude = ModelAliasDefinition::new("claude-3-7-sonnet");
        claude =
            claude.add_candidate(RouteCandidate::new("gemini", "gemini-2.5-pro").with_priority(10));
        route_table.register_alias(claude);

        let mut claude35 = ModelAliasDefinition::new("claude-3-5-sonnet");
        claude35 = claude35
            .add_candidate(RouteCandidate::new("gemini", "gemini-2.5-pro").with_priority(10));
        route_table.register_alias(claude35);

        let mut gpt4o = ModelAliasDefinition::new("gpt-4o");
        gpt4o =
            gpt4o.add_candidate(RouteCandidate::new("deepseek", "deepseek-chat").with_priority(10));
        route_table.register_alias(gpt4o);

        let mut o3 = ModelAliasDefinition::new("o3-mini");
        o3 = o3
            .add_candidate(RouteCandidate::new("deepseek", "deepseek-reasoner").with_priority(10));
        route_table.register_alias(o3);

        // 4. Smart Scheduling Aliases
        let mut smart = ModelAliasDefinition::new("coding-smart").require(
            CapabilitySet::new()
                .with(Capability::NativeTools)
                .with(Capability::Reasoning),
        );
        smart = smart.add_candidate(
            RouteCandidate::new("gemini", "gemini-2.5-pro")
                .with_capabilities(
                    CapabilitySet::new()
                        .with(Capability::NativeTools)
                        .with(Capability::Reasoning),
                )
                .with_priority(10),
        );
        route_table.register_alias(smart);

        let mut fast = ModelAliasDefinition::new("coding-fast")
            .require(CapabilitySet::new().with(Capability::NativeTools));
        fast = fast.add_candidate(
            RouteCandidate::new("deepseek", "deepseek-chat")
                .with_capabilities(CapabilitySet::new().with(Capability::NativeTools))
                .with_priority(20),
        );
        route_table.register_alias(fast);

        let mut reasoner = ModelAliasDefinition::new("coding-reasoner")
            .require(CapabilitySet::new().with(Capability::Reasoning));
        reasoner = reasoner.add_candidate(
            RouteCandidate::new("deepseek", "deepseek-reasoner")
                .with_capabilities(CapabilitySet::new().with(Capability::Reasoning))
                .with_priority(30),
        );
        route_table.register_alias(reasoner);

        let mut mini = ModelAliasDefinition::new("coding-mini");
        mini =
            mini.add_candidate(RouteCandidate::new("gemini", "gemini-2.0-flash").with_priority(10));
        route_table.register_alias(mini);

        Self {
            token: token.into(),
            route_table,
            active_requests: Arc::new(AtomicUsize::new(0)),
            total_requests: Arc::new(AtomicUsize::new(0)),
            total_input_tokens: Arc::new(AtomicUsize::new(0)),
            total_output_tokens: Arc::new(AtomicUsize::new(0)),
            total_tool_calls: Arc::new(AtomicUsize::new(0)),
            is_running: Arc::new(AtomicBool::new(true)),
            recent_requests: Arc::new(Mutex::new(VecDeque::new())),
            gemini_thought_signatures: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    fn response(status: &str, content_type: &str, body: &str) -> Vec<u8> {
        format!(
            "HTTP/1.1 {status}\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS, HEAD\r\nAccess-Control-Allow-Headers: *\r\nConnection: close\r\n\r\n{body}",
            body.len()
        )
        .into_bytes()
    }

    pub fn handle_client(&self, mut stream: TcpStream) -> std::io::Result<bool> {
        let mut buffer = [0_u8; 65_536];
        let count = stream.read(&mut buffer)?;
        if count == 0 {
            return Ok(false);
        }

        let mut raw_data = buffer[..count].to_vec();

        // Check if we have received full headers
        let header_end = if let Some(idx) = raw_data.windows(4).position(|w| w == b"\r\n\r\n") {
            Some((idx, 4))
        } else if let Some(idx) = raw_data.windows(2).position(|w| w == b"\n\n") {
            Some((idx, 2))
        } else {
            None
        };

        // Extract content length if any
        let header_str = String::from_utf8_lossy(&raw_data);
        let content_length: usize = header_str
            .lines()
            .find_map(|l| {
                let lower = l.to_lowercase();
                if lower.starts_with("content-length:") {
                    l.split(':').nth(1)?.trim().parse().ok()
                } else {
                    None
                }
            })
            .unwrap_or(0);

        if let Some((hdr_idx, sep_len)) = header_end {
            let body_start = hdr_idx + sep_len;
            while raw_data.len() - body_start < content_length {
                let mut chunk = [0_u8; 8192];
                let n = stream.read(&mut chunk)?;
                if n == 0 {
                    break;
                }
                raw_data.extend_from_slice(&chunk[..n]);
            }
        }

        let request = String::from_utf8_lossy(&raw_data);
        let mut lines = request.lines();
        let request_line = lines.next().unwrap_or_default();
        let mut parts = request_line.split_whitespace();
        let method = parts.next().unwrap_or_default();
        let raw_path = parts.next().unwrap_or_default();

        if method.eq_ignore_ascii_case("OPTIONS") {
            let response_bytes = Self::response("200 OK", "text/plain", "");
            stream.write_all(&response_bytes)?;
            stream.flush()?;
            return Ok(false);
        }

        // Clean query parameters and redundant /v1 prefixes
        let clean_path = raw_path
            .split('?')
            .next()
            .unwrap_or(raw_path)
            .trim_end_matches('/');
        let path = if clean_path.starts_with("/v1/v1/") {
            &clean_path[3..]
        } else {
            clean_path
        };

        let authorized = request.lines().any(|l| {
            let trimmed = l.trim();
            if let Some(val) = trimmed.strip_prefix("Authorization:") {
                let v = val.trim();
                if let Some(bearer) = v.strip_prefix("Bearer ") {
                    bearer.trim() == self.token
                } else if let Some(bearer) = v.strip_prefix("bearer ") {
                    bearer.trim() == self.token
                } else {
                    v == self.token
                }
            } else if let Some(val) = trimmed.strip_prefix("authorization:") {
                let v = val.trim();
                if let Some(bearer) = v.strip_prefix("Bearer ") {
                    bearer.trim() == self.token
                } else if let Some(bearer) = v.strip_prefix("bearer ") {
                    bearer.trim() == self.token
                } else {
                    v == self.token
                }
            } else if let Some(val) = trimmed.strip_prefix("api-key:") {
                val.trim() == self.token
            } else if let Some(val) = trimmed.strip_prefix("x-api-key:") {
                val.trim() == self.token
            } else {
                false
            }
        });

        // Find JSON body if any
        let body = if let Some((hdr_idx, sep_len)) = header_end {
            &request[hdr_idx + sep_len..]
        } else if let Some(idx) = request.find("\r\n\r\n") {
            &request[idx + 4..]
        } else {
            ""
        };

        let mut should_stop = false;

        // Direct upstream proxy for chat completions
        if method == "POST" && (path == "/v1/chat/completions" || path == "/chat/completions") {
            self.active_requests.fetch_add(1, Ordering::SeqCst);
            self.total_requests.fetch_add(1, Ordering::Relaxed);
            let _ = self.proxy_chat_completions(body, &mut stream);
            self.active_requests.fetch_sub(1, Ordering::SeqCst);
            return Ok(false);
        }

        let response_bytes = match (method, path) {
            ("GET", "/health") => Self::response(
                "200 OK",
                "application/json",
                r#"{"status":"ok","service":"codexling-gateway"}"#,
            ),
            ("GET", "/status") => {
                if !authorized {
                    Self::response(
                        "401 Unauthorized",
                        "application/json",
                        r#"{"error":"unauthorized"}"#,
                    )
                } else {
                    let active = self.active_requests.load(Ordering::Relaxed);
                    let total_req = self.total_requests.load(Ordering::Relaxed);
                    let in_tok = self.total_input_tokens.load(Ordering::Relaxed);
                    let out_tok = self.total_output_tokens.load(Ordering::Relaxed);
                    let tools = self.total_tool_calls.load(Ordering::Relaxed);
                    let reqs: Vec<GatewayRequestRecord> = self
                        .recent_requests
                        .lock()
                        .map(|q| q.iter().cloned().collect())
                        .unwrap_or_default();
                    let payload = serde_json::json!({
                        "running": true,
                        "bind": "127.0.0.1",
                        "active_requests": active,
                        "total_requests": total_req,
                        "total_input_tokens": in_tok,
                        "total_output_tokens": out_tok,
                        "total_tool_calls": tools,
                        "recent_requests": reqs,
                        "providers": ["google", "deepseek", "anthropic", "openai"]
                    });
                    Self::response("200 OK", "application/json", &payload.to_string())
                }
            }
            ("GET", "/v1/models") | ("GET", "/models") => {
                let payload = Self::get_dynamic_models_payload();
                Self::response("200 OK", "application/json", &payload.to_string())
            }
            ("POST", "/v1/chat/completions") | ("POST", "/chat/completions") => {
                self.active_requests.fetch_add(1, Ordering::SeqCst);
                let resp = self.process_chat_completions(body);
                self.active_requests.fetch_sub(1, Ordering::SeqCst);
                resp
            }
            ("POST", "/v1/responses") | ("POST", "/responses") => {
                self.active_requests.fetch_add(1, Ordering::SeqCst);
                let resp = self.process_responses(body);
                self.active_requests.fetch_sub(1, Ordering::SeqCst);
                resp
            }
            ("POST", "/v1/messages") | ("POST", "/messages") => {
                self.active_requests.fetch_add(1, Ordering::SeqCst);
                let resp = self.process_anthropic_messages(body);
                self.active_requests.fetch_sub(1, Ordering::SeqCst);
                resp
            }
            ("POST", "/shutdown") => {
                if !authorized {
                    Self::response(
                        "401 Unauthorized",
                        "application/json",
                        r#"{"error":"unauthorized"}"#,
                    )
                } else {
                    should_stop = true;
                    self.is_running.store(false, Ordering::Relaxed);
                    Self::response("200 OK", "application/json", r#"{"stopping":true}"#)
                }
            }
            _ => Self::response(
                "404 Not Found",
                "application/json",
                r#"{"error":"not_found"}"#,
            ),
        };

        stream.write_all(&response_bytes)?;
        stream.flush()?;
        Ok(should_stop)
    }

    fn decode_body(raw_body: &str) -> String {
        let trimmed = raw_body.trim();
        if trimmed.starts_with('{') && trimmed.ends_with('}') {
            return trimmed.to_string();
        }
        if let Some(start) = trimmed.find('{') {
            if let Some(end) = trimmed.rfind('}') {
                if start <= end {
                    return trimmed[start..=end].to_string();
                }
            }
        }
        trimmed.to_string()
    }

    fn sanitize_messages_sequence(raw_messages: Vec<serde_json::Value>) -> Vec<serde_json::Value> {
        let mut normalized = Vec::new();

        for mut msg in raw_messages {
            let role = msg
                .get("role")
                .and_then(|r| r.as_str())
                .unwrap_or("user")
                .to_string();

            // 1. Normalize developer -> system
            if role == "developer" {
                msg["role"] = serde_json::json!("system");
            }

            // 2. Filter empty assistant messages without tool_calls
            let effective_role = msg.get("role").and_then(|r| r.as_str()).unwrap_or("user");
            let has_tool_calls = msg
                .get("tool_calls")
                .and_then(|tc| tc.as_array())
                .map(|a| !a.is_empty())
                .unwrap_or(false);

            if effective_role == "assistant" && !has_tool_calls {
                if let Some(c) = msg.get("content").and_then(|c| c.as_str()) {
                    let t = c.trim();
                    if t.is_empty() || t == "(empty)" || t == "empty" {
                        continue;
                    }
                } else if msg.get("content").is_none() || msg["content"].is_null() {
                    continue;
                }
            } else if msg.get("content").is_none() || msg["content"].is_null() {
                msg["content"] = serde_json::json!("");
            }

            normalized.push(msg);
        }

        // 3. Validate and fix tool message sequencing to prevent "Messages with role 'tool' must be a response to a preceding message with 'tool_calls'"
        let mut result = Vec::new();
        let mut pending_tool_ids = std::collections::HashSet::new();

        for msg in normalized {
            let role = msg.get("role").and_then(|r| r.as_str()).unwrap_or("user");

            if role == "assistant" {
                pending_tool_ids.clear();
                if let Some(tool_calls) = msg.get("tool_calls").and_then(|tc| tc.as_array()) {
                    for tc in tool_calls {
                        if let Some(id) = tc.get("id").and_then(|i| i.as_str()) {
                            pending_tool_ids.insert(id.to_string());
                        }
                    }
                }
                result.push(msg);
            } else if role == "tool" || role == "function" {
                let tool_id = msg
                    .get("tool_call_id")
                    .and_then(|i| i.as_str())
                    .unwrap_or("");
                if !tool_id.is_empty() && pending_tool_ids.contains(tool_id) {
                    result.push(msg);
                } else {
                    // Orphaned tool response: convert to user message with tool prefix to preserve context and satisfy API constraints
                    let content_str = if let Some(s) = msg.get("content").and_then(|c| c.as_str()) {
                        s.to_string()
                    } else {
                        msg.get("content")
                            .map(|c| c.to_string())
                            .unwrap_or_default()
                    };
                    let converted_content = if content_str.trim().is_empty() {
                        "[工具输出]".to_string()
                    } else {
                        format!("[工具输出]: {content_str}")
                    };
                    result.push(serde_json::json!({
                        "role": "user",
                        "content": converted_content
                    }));
                }
            } else {
                pending_tool_ids.clear();
                result.push(msg);
            }
        }

        if result.is_empty() {
            result.push(serde_json::json!({"role": "user", "content": "Hello"}));
        }

        result
    }

    fn proxy_chat_completions(&self, body: &str, stream: &mut TcpStream) -> std::io::Result<bool> {
        let clean_json = Self::decode_body(body);
        let raw_req: serde_json::Value = match serde_json::from_str(&clean_json) {
            Ok(v) => v,
            Err(e) => {
                eprintln!(
                    "[Gateway] Error parsing JSON body: {:?}, raw: {:?}",
                    e, body
                );
                let resp = Self::response(
                    "400 Bad Request",
                    "application/json",
                    &format!(
                        r#"{{"error":{{"message":"JSON parse error: {}","type":"invalid_request_error"}}}}"#,
                        e
                    ),
                );
                stream.write_all(&resp)?;
                stream.flush()?;
                return Ok(true);
            }
        };

        let requested_model = raw_req
            .get("model")
            .and_then(|m| m.as_str())
            .unwrap_or("gpt-5.6");
        let is_stream = raw_req
            .get("stream")
            .and_then(|s| s.as_bool())
            .unwrap_or(false);
        let start_time = std::time::Instant::now();
        let now_unix = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        // Format current time "HH:MM:SS" in Local (UTC+8)
        let time_str = {
            let total_sec = now_unix % 86400;
            let h = (total_sec / 3600 + 8) % 24;
            let m = (total_sec % 3600) / 60;
            let s = total_sec % 60;
            format!("{:02}:{:02}:{:02}", h, m, s)
        };

        let upstream = match Self::resolve_upstream_endpoint(requested_model) {
            Ok(u) => u,
            Err(err_msg) => {
                // Strict isolation: Return error immediately, NEVER fallback to another paid provider!
                let hdr = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS, HEAD\r\nAccess-Control-Allow-Headers: *\r\nConnection: close\r\n\r\n";
                stream.write_all(hdr.as_bytes())?;
                let sse_err = format!(
                    "data: {{\"id\":\"resp_err\",\"object\":\"chat.completion.chunk\",\"created\":{},\"model\":\"{}\",\"choices\":[{{\"index\":0,\"delta\":{{\"role\":\"assistant\",\"content\":\"[提示] {}\"}},\"finish_reason\":null}}]}}\n\n",
                    now_unix, requested_model, err_msg
                );
                stream.write_all(sse_err.as_bytes())?;
                let finish = format!(
                    "data: {{\"id\":\"resp_finish\",\"object\":\"chat.completion.chunk\",\"created\":{},\"model\":\"{}\",\"choices\":[{{\"index\":0,\"delta\":{{}},\"finish_reason\":\"stop\"}}]}}\n\ndata: [DONE]\n\n",
                    now_unix, requested_model
                );
                stream.write_all(finish.as_bytes())?;
                stream.flush()?;
                return Ok(true);
            }
        };

        let raw_messages = raw_req
            .get("messages")
            .and_then(|m| m.as_array())
            .cloned()
            .unwrap_or_default();
        let clean_messages = Self::sanitize_messages_sequence(raw_messages);

        if let Some(codex_home) = upstream.codex_home.as_deref() {
            return self.proxy_codex_subscription(
                requested_model,
                &upstream.target_model,
                codex_home,
                &clean_messages,
                is_stream,
                now_unix,
                &time_str,
                start_time,
                stream,
            );
        }

        let input_tokens = (body.len() / 4).max(1);
        self.total_input_tokens
            .fetch_add(input_tokens, Ordering::Relaxed);

        if upstream.provider_name == "Google Gemini" {
            return self.proxy_gemini_oauth(
                requested_model,
                &upstream,
                &raw_req,
                &clean_messages,
                is_stream,
                now_unix,
                &time_str,
                start_time,
                stream,
            );
        }

        let mut payload = serde_json::json!({
            "model": upstream.target_model,
            "messages": clean_messages,
            "stream": is_stream,
        });

        if let Some(t) = raw_req.get("temperature") {
            payload["temperature"] = t.clone();
        }
        if let Some(p) = raw_req.get("top_p") {
            payload["top_p"] = p.clone();
        }
        if let Some(max) = raw_req
            .get("max_tokens")
            .or_else(|| raw_req.get("max_completion_tokens"))
        {
            payload["max_tokens"] = max.clone();
        }
        if let Some(tools) = raw_req.get("tools") {
            payload["tools"] = tools.clone();
        }
        if let Some(tc) = raw_req.get("tool_choice") {
            payload["tool_choice"] = tc.clone();
        }

        let payload_str = payload.to_string();

        let mut cmd = std::process::Command::new("curl");
        cmd.arg("-s")
            .arg("-N")
            .arg("-X")
            .arg("POST")
            .arg(&upstream.url)
            .arg("-H")
            .arg(format!("Authorization: {}", upstream.auth_header))
            .arg("-H")
            .arg("Content-Type: application/json")
            .arg("-d")
            .arg(&payload_str)
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::null());
        for (name, value) in &upstream.extra_headers {
            cmd.arg("-H").arg(format!("{name}: {value}"));
        }

        let mut child = match cmd.spawn() {
            Ok(c) => c,
            Err(e) => {
                let resp = Self::response(
                    "502 Bad Gateway",
                    "application/json",
                    &format!(
                        r#"{{"error":{{"message":"Failed to spawn upstream process: {}","type":"upstream_error"}}}}"#,
                        e
                    ),
                );
                stream.write_all(&resp)?;
                stream.flush()?;
                return Ok(true);
            }
        };

        let stdout = match child.stdout.take() {
            Some(s) => s,
            None => {
                let resp = Self::response(
                    "502 Bad Gateway",
                    "application/json",
                    r#"{"error":{"message":"Failed to capture upstream process stdout","type":"upstream_error"}}"#,
                );
                stream.write_all(&resp)?;
                stream.flush()?;
                return Ok(true);
            }
        };

        use std::io::BufRead;
        let mut reader = std::io::BufReader::new(stdout);
        let mut header_sent = false;
        let mut emitted_done = false;
        let mut emitted_any_data = false;
        let mut output_chars = 0;
        let mut ttft_ms = 0;

        let mut line_buf = String::new();
        while let Ok(n) = reader.read_line(&mut line_buf) {
            if n == 0 {
                break;
            }
            let trimmed = line_buf.trim();

            if !header_sent {
                header_sent = true;
                ttft_ms = start_time.elapsed().as_millis() as u64;
                if is_stream {
                    let hdr = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS, HEAD\r\nAccess-Control-Allow-Headers: *\r\nConnection: close\r\n\r\n";
                    stream.write_all(hdr.as_bytes())?;
                } else {
                    let hdr = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS, HEAD\r\nAccess-Control-Allow-Headers: *\r\nConnection: close\r\n\r\n";
                    stream.write_all(hdr.as_bytes())?;
                }
            }

            if is_stream {
                // Check if upstream returned a raw JSON error (either {...} or [{...}]) instead of SSE data
                if (trimmed.starts_with('{') || trimmed.starts_with('['))
                    && trimmed.contains("\"error\"")
                {
                    let err_msg_opt =
                        if let Ok(err_json) = serde_json::from_str::<serde_json::Value>(trimmed) {
                            let err_obj = if let Some(arr) = err_json.as_array() {
                                arr.first().and_then(|item| item.get("error"))
                            } else {
                                err_json.get("error")
                            };
                            err_obj
                                .and_then(|e| e.get("message"))
                                .and_then(|m| m.as_str())
                                .map(|s| s.to_string())
                        } else {
                            None
                        };

                    let msg = err_msg_opt.unwrap_or_else(|| "上游 Google 模型响应异常".to_string());
                    let sse_err = format!(
                        "data: {{\"id\":\"resp_err\",\"object\":\"chat.completion.chunk\",\"created\":{},\"model\":\"{}\",\"choices\":[{{\"index\":0,\"delta\":{{\"role\":\"assistant\",\"content\":\"[Google 提示] {}\"}},\"finish_reason\":null}}]}}\n\n",
                        now_unix, requested_model, msg
                    );
                    stream.write_all(sse_err.as_bytes())?;
                    let sse_stop = format!(
                        "data: {{\"id\":\"resp_stop\",\"object\":\"chat.completion.chunk\",\"created\":{},\"model\":\"{}\",\"choices\":[{{\"index\":0,\"delta\":{{}},\"finish_reason\":\"stop\"}}]}}\n\ndata: [DONE]\n\n",
                        now_unix, requested_model
                    );
                    stream.write_all(sse_stop.as_bytes())?;
                    stream.flush()?;
                    emitted_any_data = true;
                    emitted_done = true;
                    line_buf.clear();
                    break;
                }

                if trimmed.starts_with("data:") {
                    emitted_any_data = true;
                    output_chars += trimmed.len();
                }
                if trimmed.contains("[DONE]") {
                    emitted_done = true;
                }
            }

            stream.write_all(line_buf.as_bytes())?;
            stream.flush()?;
            line_buf.clear();
        }

        let _ = child.wait();

        let latency_ms = start_time.elapsed().as_millis() as u64;
        let output_tokens = (output_chars / 4).max(12);
        self.total_output_tokens
            .fetch_add(output_tokens, Ordering::Relaxed);

        if is_stream {
            // Never fabricate a successful assistant answer when the selected
            // provider produced no bytes. This used to conceal upstream auth,
            // quota, and unsupported-model errors and looked like a fallback.
            if !header_sent || !emitted_any_data {
                if !header_sent {
                    let hdr = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS, HEAD\r\nAccess-Control-Allow-Headers: *\r\nConnection: close\r\n\r\n";
                    stream.write_all(hdr.as_bytes())?;
                }
                let error = format!(
                    "data: {{\"id\":\"resp_upstream_error\",\"object\":\"chat.completion.chunk\",\"created\":{},\"model\":\"{}\",\"choices\":[{{\"index\":0,\"delta\":{{\"role\":\"assistant\",\"content\":\"[网关错误] 选定账号的上游未返回有效响应；请求未回退或降级。\"}},\"finish_reason\":null}}]}}\n\n",
                    now_unix, requested_model
                );
                stream.write_all(error.as_bytes())?;
                stream.flush()?;
            }

            if !emitted_done {
                let finish_event = format!(
                    "data: {{\"id\":\"resp_finish\",\"object\":\"chat.completion.chunk\",\"created\":{},\"model\":\"{}\",\"choices\":[{{\"index\":0,\"delta\":{{}},\"finish_reason\":\"stop\"}}]}}\n\ndata: [DONE]\n\n",
                    now_unix, requested_model
                );
                stream.write_all(finish_event.as_bytes())?;
                stream.flush()?;
            }
        }

        // Save request record to recent_requests deque
        let record = GatewayRequestRecord {
            id: format!("req_{}_{}", now_unix, requested_model.replace(' ', "_")),
            time: time_str,
            agent: "Hermes".into(),
            ingress_protocol: "OpenAI Chat".into(),
            model_alias: requested_model.to_string(),
            target_provider: upstream.provider_name.clone(),
            target_model: upstream.target_model.clone(),
            latency_ms,
            ttft_ms: if ttft_ms > 0 { ttft_ms } else { latency_ms / 3 },
            tokens: input_tokens + output_tokens,
            fidelity: "100%".into(),
            status: "200 OK".into(),
        };

        if let Ok(mut lock) = self.recent_requests.lock() {
            lock.push_front(record);
            if lock.len() > 50 {
                lock.pop_back();
            }
        }

        Ok(true)
    }

    /// Translate OpenAI Chat Completions to Antigravity Cloud Code's OAuth-only
    /// `GenerateContentRequest` envelope.  This includes function tools: they
    /// are converted into Gemini `functionDeclarations`, never routed to a
    /// different provider.
    fn proxy_gemini_oauth(
        &self,
        requested_model: &str,
        upstream: &UpstreamEndpoint,
        raw_req: &serde_json::Value,
        messages: &[serde_json::Value],
        is_stream: bool,
        now_unix: u64,
        time_str: &str,
        start_time: std::time::Instant,
        stream: &mut TcpStream,
    ) -> std::io::Result<bool> {
        let mut system_parts = Vec::new();
        let mut contents = Vec::new();
        for message in messages {
            let role = message
                .get("role")
                .and_then(|value| value.as_str())
                .unwrap_or("user");
            if role == "system" {
                if let Some(text) = Self::message_text(message.get("content")) {
                    if !text.trim().is_empty() {
                        system_parts.push(serde_json::json!({"text": text}));
                    }
                }
                continue;
            }

            let mut parts = Vec::new();
            if let Some(text) = Self::message_text(message.get("content")) {
                if !text.trim().is_empty() {
                    parts.push(serde_json::json!({"text": text}));
                }
            }
            if role == "assistant" {
                if let Some(tool_calls) =
                    message.get("tool_calls").and_then(|value| value.as_array())
                {
                    for call in tool_calls {
                        let Some(function) = call.get("function") else {
                            continue;
                        };
                        let Some(name) = function.get("name").and_then(|value| value.as_str())
                        else {
                            continue;
                        };
                        let args = function
                            .get("arguments")
                            .and_then(|value| value.as_str())
                            .and_then(|value| serde_json::from_str::<serde_json::Value>(value).ok())
                            .filter(|value| value.is_object())
                            .unwrap_or_else(|| serde_json::json!({}));
                        let native_call = serde_json::json!({"name": name, "args": args});
                        // Cloud Code returns a thought signature with some
                        // function calls. Replaying it is required when the
                        // client submits that call's tool result.
                        let mut native_part = serde_json::json!({"functionCall": native_call});
                        let signature = function
                            .get("thought_signature")
                            .or_else(|| function.get("thoughtSignature"))
                            .and_then(|value| value.as_str())
                            .map(str::to_string)
                            .or_else(|| {
                                call.get("id")
                                    .and_then(|value| value.as_str())
                                    .and_then(|id| {
                                        self.gemini_thought_signatures.lock().ok()?.get(id).cloned()
                                    })
                            });
                        if let Some(signature) = signature {
                            native_part["thoughtSignature"] = serde_json::json!(signature);
                        }
                        parts.push(native_part);
                    }
                }
            } else if role == "tool" {
                let call_id = message
                    .get("tool_call_id")
                    .and_then(|value| value.as_str())
                    .unwrap_or("");
                let Some(name) = Self::openai_tool_name_for_call(messages, call_id) else {
                    return Self::write_gateway_error(
                        stream,
                        requested_model,
                        is_stream,
                        now_unix,
                        "Gemini 工具结果缺少对应的工具名称。请求未回退到其他供应商。",
                    );
                };
                let response = Self::message_text(message.get("content"))
                    .and_then(|text| serde_json::from_str::<serde_json::Value>(&text).ok())
                    .unwrap_or_else(|| serde_json::json!({"result": Self::message_text(message.get("content")).unwrap_or_default()}));
                parts.push(
                    serde_json::json!({"functionResponse": {"name": name, "response": response}}),
                );
            }
            if !parts.is_empty() {
                contents.push(serde_json::json!({
                    "role": if role == "assistant" { "model" } else { "user" },
                    "parts": parts
                }));
            }
        }
        if contents.is_empty() {
            return Self::write_gateway_error(
                stream,
                requested_model,
                is_stream,
                now_unix,
                "请求中没有可发送给 Gemini 的文本内容。",
            );
        }

        let mut generation_request = serde_json::json!({"contents": contents});
        if !system_parts.is_empty() {
            generation_request["systemInstruction"] = serde_json::json!({"parts": system_parts});
        }
        let mut generation = serde_json::Map::new();
        if let Some(value) = raw_req.get("temperature") {
            generation.insert("temperature".into(), value.clone());
        }
        if let Some(value) = raw_req.get("top_p") {
            generation.insert("topP".into(), value.clone());
        }
        if let Some(value) = raw_req
            .get("max_tokens")
            .or_else(|| raw_req.get("max_completion_tokens"))
        {
            generation.insert("maxOutputTokens".into(), value.clone());
        }
        if !generation.is_empty() {
            generation_request["generationConfig"] = serde_json::Value::Object(generation);
        }
        if let Some(tools) = Self::openai_tools_to_gemini(raw_req) {
            generation_request["tools"] = tools;
        }
        if let Some(tool_config) = Self::openai_tool_choice_to_gemini(raw_req.get("tool_choice")) {
            generation_request["toolConfig"] = tool_config;
        }

        let project = upstream
            .project
            .as_deref()
            .filter(|value| !value.trim().is_empty());
        let Some(project) = project else {
            return Self::write_gateway_error(
                stream,
                requested_model,
                is_stream,
                now_unix,
                "Google OAuth 账号缺少 Cloud Code 项目，无法调用 Antigravity。",
            );
        };
        let payload = Self::cloud_code_generate_payload(
            project,
            &upstream.target_model,
            generation_request,
            &format!("codexling-{now_unix}"),
        );

        let mut cmd = std::process::Command::new("curl");
        cmd.arg("-s")
            .arg("-X")
            .arg("POST")
            .arg(&upstream.url)
            .arg("-H")
            .arg(format!("Authorization: {}", upstream.auth_header))
            .arg("-H")
            .arg("Content-Type: application/json")
            .arg("-H")
            .arg("User-Agent: antigravity")
            .arg("-H")
            .arg(r#"Client-Metadata: {"ideType":"ANTIGRAVITY"}"#)
            .arg("-d")
            .arg(payload.to_string())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::null());
        for (name, value) in &upstream.extra_headers {
            cmd.arg("-H").arg(format!("{name}: {value}"));
        }
        let output = match cmd.output() {
            Ok(output) => output,
            Err(error) => {
                return Self::write_gateway_error(
                    stream,
                    requested_model,
                    is_stream,
                    now_unix,
                    &format!("无法启动 Gemini OAuth 请求：{error}"),
                )
            }
        };
        let body: serde_json::Value = match serde_json::from_slice(&output.stdout) {
            Ok(body) => body,
            Err(_) => {
                return Self::write_gateway_error(
                    stream,
                    requested_model,
                    is_stream,
                    now_unix,
                    "Gemini OAuth 上游返回了无效响应。",
                )
            }
        };
        if let Some(message) = body
            .get("error")
            .and_then(|error| error.get("message"))
            .and_then(|value| value.as_str())
        {
            return Self::write_gateway_error(
                stream,
                requested_model,
                is_stream,
                now_unix,
                &format!("Gemini OAuth 请求失败：{message}"),
            );
        }
        let message = self.cloud_code_response_message(&body);
        let Some(message) = message else {
            return Self::write_gateway_error(
                stream,
                requested_model,
                is_stream,
                now_unix,
                "Gemini OAuth 上游未返回文本或工具调用结果。",
            );
        };
        let latency_ms = start_time.elapsed().as_millis() as u64;
        let answer_len = message
            .get("content")
            .and_then(|value| value.as_str())
            .map(str::len)
            .unwrap_or(0);
        self.total_output_tokens
            .fetch_add((answer_len / 4).max(1), Ordering::Relaxed);
        let model = serde_json::to_string(requested_model).unwrap_or_else(|_| "\"google\"".into());
        let message_json = serde_json::to_string(&message)
            .unwrap_or_else(|_| "{\"role\":\"assistant\",\"content\":\"\"}".into());
        let tool_calls = message.get("tool_calls").cloned();
        let response = if is_stream {
            if let Some(tool_calls) = tool_calls {
                let tool_calls_json =
                    serde_json::to_string(&tool_calls).unwrap_or_else(|_| "[]".into());
                format!("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\ndata: {{\"id\":\"gemini_oauth\",\"object\":\"chat.completion.chunk\",\"created\":{now_unix},\"model\":{model},\"choices\":[{{\"index\":0,\"delta\":{{\"role\":\"assistant\",\"tool_calls\":{tool_calls_json}}},\"finish_reason\":null}}]}}\n\ndata: {{\"id\":\"gemini_oauth\",\"object\":\"chat.completion.chunk\",\"created\":{now_unix},\"model\":{model},\"choices\":[{{\"index\":0,\"delta\":{{}},\"finish_reason\":\"tool_calls\"}}]}}\n\ndata: [DONE]\n\n")
            } else {
                let answer_json = serde_json::to_string(
                    message
                        .get("content")
                        .and_then(|value| value.as_str())
                        .unwrap_or(""),
                )
                .unwrap_or_else(|_| "\"\"".into());
                format!("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\ndata: {{\"id\":\"gemini_oauth\",\"object\":\"chat.completion.chunk\",\"created\":{now_unix},\"model\":{model},\"choices\":[{{\"index\":0,\"delta\":{{\"role\":\"assistant\",\"content\":{answer_json}}},\"finish_reason\":null}}]}}\n\ndata: {{\"id\":\"gemini_oauth\",\"object\":\"chat.completion.chunk\",\"created\":{now_unix},\"model\":{model},\"choices\":[{{\"index\":0,\"delta\":{{}},\"finish_reason\":\"stop\"}}]}}\n\ndata: [DONE]\n\n")
            }
        } else {
            let finish_reason = if tool_calls.is_some() {
                "tool_calls"
            } else {
                "stop"
            };
            format!("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n{{\"id\":\"gemini_oauth\",\"object\":\"chat.completion\",\"created\":{now_unix},\"model\":{model},\"choices\":[{{\"index\":0,\"message\":{message_json},\"finish_reason\":\"{finish_reason}\"}}]}}")
        };
        stream.write_all(response.as_bytes())?;
        stream.flush()?;
        if let Ok(mut records) = self.recent_requests.lock() {
            records.push_front(GatewayRequestRecord {
                id: format!("req_{}_{}", now_unix, requested_model.replace(' ', "_")),
                time: time_str.into(),
                agent: "Hermes".into(),
                ingress_protocol: "OpenAI Chat".into(),
                model_alias: requested_model.into(),
                target_provider: "Google Gemini".into(),
                target_model: upstream.target_model.clone(),
                latency_ms,
                ttft_ms: latency_ms,
                tokens: (answer_len / 4).max(1),
                fidelity: "OAuth native".into(),
                status: "200 OK".into(),
            });
        }
        Ok(true)
    }

    fn cloud_code_generate_payload(
        project: &str,
        model: &str,
        request: serde_json::Value,
        request_id: &str,
    ) -> serde_json::Value {
        serde_json::json!({
            "project": project,
            "model": model,
            "request": request,
            "requestId": request_id,
            "userAgent": "Codexling Gateway"
        })
    }

    /// Cloud Code wraps the native Vertex/Gemini response in `response`, while
    /// a few compatible deployments return the native payload directly.
    #[cfg(test)]
    fn cloud_code_response_text(body: &serde_json::Value) -> Option<String> {
        body.pointer("/response/candidates/0/content/parts")
            .or_else(|| body.pointer("/candidates/0/content/parts"))
            .and_then(|value| value.as_array())
            .map(|parts| {
                parts
                    .iter()
                    .filter_map(|part| part.get("text").and_then(|text| text.as_str()))
                    .collect::<Vec<_>>()
                    .join("\n")
            })
            .filter(|text| !text.trim().is_empty())
    }

    fn openai_tools_to_gemini(raw_req: &serde_json::Value) -> Option<serde_json::Value> {
        let declarations = raw_req
            .get("tools")?
            .as_array()?
            .iter()
            .filter_map(|tool| {
                let function = tool.get("function")?;
                let name = function.get("name")?.as_str()?;
                let mut declaration = serde_json::Map::new();
                declaration.insert("name".into(), serde_json::Value::String(name.into()));
                if let Some(description) = function.get("description") {
                    declaration.insert("description".into(), description.clone());
                }
                declaration.insert(
                    "parameters".into(),
                    Self::normalize_tool_schema(function.get("parameters")),
                );
                Some(serde_json::Value::Object(declaration))
            })
            .collect::<Vec<_>>();
        (!declarations.is_empty())
            .then(|| serde_json::json!([{"functionDeclarations": declarations}]))
    }

    /// Hermes can expose third-party custom tools with OpenAI-flavoured schema
    /// extensions (or an older `$schema` declaration).  Cloud Code forwards
    /// Claude tools to a Draft 2020-12 validator, which rejects an entire
    /// request when one tool is malformed.  Keep the portable JSON Schema
    /// subset and discard only non-standard/invalid extensions.
    fn normalize_tool_schema(schema: Option<&serde_json::Value>) -> serde_json::Value {
        fn normalize(value: &serde_json::Value) -> Option<serde_json::Value> {
            if value.is_boolean() {
                return Some(value.clone());
            }
            let object = value.as_object()?;
            let mut result = serde_json::Map::new();

            if let Some(description) = object.get("description").and_then(|v| v.as_str()) {
                result.insert("description".into(), serde_json::json!(description));
            }
            if let Some(title) = object.get("title").and_then(|v| v.as_str()) {
                result.insert("title".into(), serde_json::json!(title));
            }
            if let Some(reference) = object.get("$ref").and_then(|v| v.as_str()) {
                result.insert("$ref".into(), serde_json::json!(reference));
            }
            if let Some(kind) = object.get("type") {
                let valid_kind = |kind: &str| {
                    matches!(
                        kind,
                        "object" | "array" | "string" | "number" | "integer" | "boolean" | "null"
                    )
                };
                if let Some(kind) = kind.as_str().filter(|kind| valid_kind(kind)) {
                    result.insert("type".into(), serde_json::json!(kind));
                } else if let Some(kinds) = kind.as_array() {
                    let kinds = kinds
                        .iter()
                        .filter_map(|value| value.as_str())
                        .filter(|kind| valid_kind(kind))
                        .collect::<Vec<_>>();
                    if !kinds.is_empty() {
                        result.insert("type".into(), serde_json::json!(kinds));
                    }
                }
            }
            if let Some(properties) = object.get("properties").and_then(|v| v.as_object()) {
                let properties = properties
                    .iter()
                    .filter_map(|(name, value)| normalize(value).map(|value| (name.clone(), value)))
                    .collect::<serde_json::Map<_, _>>();
                result.insert("properties".into(), serde_json::Value::Object(properties));
            }
            if let Some(required) = object.get("required").and_then(|v| v.as_array()) {
                let required = required
                    .iter()
                    .filter_map(|value| value.as_str())
                    .collect::<Vec<_>>();
                result.insert("required".into(), serde_json::json!(required));
            }
            if let Some(items) = object.get("items").and_then(normalize) {
                result.insert("items".into(), items);
            }
            if let Some(additional) = object.get("additionalProperties").and_then(normalize) {
                result.insert("additionalProperties".into(), additional);
            }
            for keyword in ["allOf", "anyOf", "oneOf"] {
                if let Some(values) = object.get(keyword).and_then(|value| value.as_array()) {
                    let values = values.iter().filter_map(normalize).collect::<Vec<_>>();
                    if !values.is_empty() {
                        result.insert(keyword.into(), serde_json::Value::Array(values));
                    }
                }
            }
            if let Some(values) = object.get("enum").and_then(|value| value.as_array()) {
                result.insert("enum".into(), serde_json::Value::Array(values.clone()));
            }
            for keyword in [
                "const",
                "default",
                "minimum",
                "maximum",
                "exclusiveMinimum",
                "exclusiveMaximum",
                "multipleOf",
                "minLength",
                "maxLength",
                "pattern",
                "format",
                "minItems",
                "maxItems",
                "uniqueItems",
                "minProperties",
                "maxProperties",
            ] {
                if let Some(value) = object.get(keyword) {
                    result.insert(keyword.into(), value.clone());
                }
            }
            Some(serde_json::Value::Object(result))
        }

        let mut normalized = schema
            .and_then(normalize)
            .unwrap_or_else(|| serde_json::json!({}));
        if !normalized.is_object() {
            normalized = serde_json::json!({});
        }
        // Function arguments are always an object for the Gemini/Claude tool
        // bridge.  A malformed top-level `type` must not poison all tools.
        if normalized.get("type").is_none() {
            normalized["type"] = serde_json::json!("object");
        }
        normalized
    }

    fn openai_tool_choice_to_gemini(
        choice: Option<&serde_json::Value>,
    ) -> Option<serde_json::Value> {
        let choice = choice?;
        let mut config = serde_json::Map::new();
        if let Some(name) = choice
            .pointer("/function/name")
            .and_then(|value| value.as_str())
        {
            config.insert("mode".into(), serde_json::json!("ANY"));
            config.insert("allowedFunctionNames".into(), serde_json::json!([name]));
        } else {
            match choice.as_str() {
                Some("none") => {
                    config.insert("mode".into(), serde_json::json!("NONE"));
                }
                Some("required") => {
                    config.insert("mode".into(), serde_json::json!("ANY"));
                }
                Some("auto") | None => return None,
                Some(_) => return None,
            }
        }
        Some(serde_json::json!({"functionCallingConfig": config}))
    }

    fn openai_tool_name_for_call(messages: &[serde_json::Value], call_id: &str) -> Option<String> {
        messages.iter().rev().find_map(|message| {
            message
                .get("tool_calls")?
                .as_array()?
                .iter()
                .find_map(|call| {
                    (call.get("id").and_then(|value| value.as_str()) == Some(call_id))
                        .then(|| {
                            call.pointer("/function/name")
                                .and_then(|value| value.as_str())
                                .map(str::to_string)
                        })
                        .flatten()
                })
        })
    }

    fn cloud_code_response_message(&self, body: &serde_json::Value) -> Option<serde_json::Value> {
        let parts = body
            .pointer("/response/candidates/0/content/parts")
            .or_else(|| body.pointer("/candidates/0/content/parts"))?
            .as_array()?;
        let text = parts
            .iter()
            .filter_map(|part| part.get("text").and_then(|text| text.as_str()))
            .collect::<Vec<_>>()
            .join("\n");
        let tool_calls = parts
            .iter()
            .filter_map(|part| {
                let call = part.get("functionCall")?;
                let name = call.get("name")?.as_str()?;
                let args = call
                    .get("args")
                    .cloned()
                    .unwrap_or_else(|| serde_json::json!({}));
                let arguments = serde_json::to_string(&args).ok()?;
                let mut function = serde_json::json!({"name":name,"arguments":arguments});
                let call_id = format!(
                    "call_gemini_{}",
                    self.total_tool_calls.fetch_add(1, Ordering::Relaxed)
                );
                if let Some(signature) = part
                    .get("thoughtSignature")
                    .or_else(|| part.get("thought_signature"))
                    .or_else(|| call.get("thoughtSignature"))
                    .or_else(|| call.get("thought_signature"))
                    .and_then(|value| value.as_str())
                {
                    // This vendor extension is ignored by ordinary OpenAI
                    // providers but preserves this Gemini call's required state.
                    function["thought_signature"] = serde_json::json!(signature);
                    if let Ok(mut cache) = self.gemini_thought_signatures.lock() {
                        if cache.len() >= 1024 {
                            cache.clear();
                        }
                        cache.insert(call_id.clone(), signature.to_string());
                    }
                }
                Some(serde_json::json!({"id": call_id, "type":"function", "function":function}))
            })
            .collect::<Vec<_>>();
        if text.trim().is_empty() && tool_calls.is_empty() {
            return None;
        }
        let mut message = serde_json::json!({"role":"assistant", "content": if text.trim().is_empty() { serde_json::Value::Null } else { serde_json::Value::String(text) }});
        if !tool_calls.is_empty() {
            message["tool_calls"] = serde_json::Value::Array(tool_calls);
        }
        Some(message)
    }

    /// Bridge a ChatGPT/Codex subscription through the local Codex client.
    /// This is deliberately a single-account process: `CODEX_HOME` is the
    /// account's private runtime directory and no API key or other account is
    /// ever consulted.
    fn proxy_codex_subscription(
        &self,
        requested_model: &str,
        target_model: &str,
        codex_home: &str,
        messages: &[serde_json::Value],
        is_stream: bool,
        now_unix: u64,
        time_str: &str,
        start_time: std::time::Instant,
        stream: &mut TcpStream,
    ) -> std::io::Result<bool> {
        if let Err(message) = Self::prepare_codex_auth(codex_home) {
            return Self::write_gateway_error(
                stream,
                requested_model,
                is_stream,
                now_unix,
                &message,
            );
        }

        let prompt = messages
            .iter()
            .filter_map(|message| {
                let role = message
                    .get("role")
                    .and_then(|value| value.as_str())
                    .unwrap_or("user");
                Self::message_text(message.get("content")).map(|text| format!("{role}: {text}"))
            })
            .collect::<Vec<_>>()
            .join("\n\n");
        if prompt.trim().is_empty() {
            return Self::write_gateway_error(
                stream,
                requested_model,
                is_stream,
                now_unix,
                "请求中没有可发送给 Codex 的文本内容。",
            );
        }

        let output_path = std::env::temp_dir().join(format!(
            "codexling-gateway-{}-{}.txt",
            std::process::id(),
            now_unix
        ));
        let instruction = format!("Do not use tools. Answer the supplied conversation as a concise assistant response.\n\n{prompt}");
        let result = std::process::Command::new("codex")
            .env("CODEX_HOME", codex_home)
            .arg("exec")
            .arg("--ephemeral")
            .arg("--skip-git-repo-check")
            .arg("--sandbox")
            .arg("read-only")
            .arg("--output-last-message")
            .arg(&output_path)
            .arg("--model")
            .arg(target_model)
            .arg(instruction)
            .output();

        let answer = match result {
            Ok(output) if output.status.success() => std::fs::read_to_string(&output_path)
                .ok()
                .filter(|text| !text.trim().is_empty()),
            Ok(output) => {
                let detail = String::from_utf8_lossy(&output.stderr);
                let trimmed = detail.trim();
                let message = if trimmed.is_empty() {
                    "Codex 上游调用失败，未执行回退。"
                } else {
                    trimmed
                };
                None.or_else(|| Some(format!("[ERROR] {message}")))
            }
            Err(error) => Some(format!("[ERROR] 无法启动本机 Codex 会话：{error}")),
        };
        let _ = std::fs::remove_file(&output_path);

        let Some(answer) = answer else {
            return Self::write_gateway_error(
                stream,
                requested_model,
                is_stream,
                now_unix,
                "Codex 上游未返回回答；未执行回退。",
            );
        };
        if let Some(error) = answer.strip_prefix("[ERROR] ") {
            return Self::write_gateway_error(stream, requested_model, is_stream, now_unix, error);
        }

        let latency_ms = start_time.elapsed().as_millis() as u64;
        let escaped_answer =
            serde_json::to_string(&answer).unwrap_or_else(|_| "\"Codex 输出无法编码\"".into());
        let response = if is_stream {
            format!(
                "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\ndata: {{\"id\":\"resp_codex\",\"object\":\"chat.completion.chunk\",\"created\":{now_unix},\"model\":{model},\"choices\":[{{\"index\":0,\"delta\":{{\"role\":\"assistant\",\"content\":{answer}}},\"finish_reason\":null}}]}}\n\ndata: {{\"id\":\"resp_codex\",\"object\":\"chat.completion.chunk\",\"created\":{now_unix},\"model\":{model},\"choices\":[{{\"index\":0,\"delta\":{{}},\"finish_reason\":\"stop\"}}]}}\n\ndata: [DONE]\n\n",
                model = serde_json::to_string(requested_model).unwrap(), answer = escaped_answer,
            )
        } else {
            format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n{{\"id\":\"resp_codex\",\"object\":\"chat.completion\",\"created\":{now_unix},\"model\":{model},\"choices\":[{{\"index\":0,\"message\":{{\"role\":\"assistant\",\"content\":{answer}}},\"finish_reason\":\"stop\"}}]}}",
                model = serde_json::to_string(requested_model).unwrap(), answer = escaped_answer,
            )
        };
        stream.write_all(response.as_bytes())?;
        stream.flush()?;
        if let Ok(mut lock) = self.recent_requests.lock() {
            lock.push_front(GatewayRequestRecord {
                id: format!("req_{}_{}", now_unix, requested_model.replace(' ', "_")),
                time: time_str.into(),
                agent: "Hermes".into(),
                ingress_protocol: "OpenAI Chat".into(),
                model_alias: requested_model.into(),
                target_provider: "OpenAI / Codex".into(),
                target_model: target_model.into(),
                latency_ms,
                ttft_ms: latency_ms,
                tokens: (answer.len() / 4).max(1),
                fidelity: "100%".into(),
                status: "200 OK".into(),
            });
        }
        Ok(true)
    }

    fn message_text(content: Option<&serde_json::Value>) -> Option<String> {
        match content? {
            serde_json::Value::String(text) => Some(text.clone()),
            serde_json::Value::Array(parts) => Some(
                parts
                    .iter()
                    .filter_map(|part| {
                        part.get("text")
                            .and_then(|value| value.as_str())
                            .map(str::to_string)
                    })
                    .collect::<Vec<_>>()
                    .join("\n"),
            ),
            _ => None,
        }
    }

    fn prepare_codex_auth(codex_home: &str) -> Result<(), String> {
        let home = std::path::Path::new(codex_home);
        let source = home.join("oauth_token.json");
        let raw = std::fs::read_to_string(&source)
            .map_err(|_| "Codex 账号会话文件不存在。".to_string())?;
        let token: serde_json::Value =
            serde_json::from_str(&raw).map_err(|_| "Codex 账号会话文件格式无效。".to_string())?;
        let access = token
            .get("accessToken")
            .and_then(|v| v.as_str())
            .ok_or("Codex 会话缺少 access token。")?;
        let refresh = token
            .get("refreshToken")
            .and_then(|v| v.as_str())
            .ok_or("Codex 会话缺少 refresh token。")?;
        let id = token
            .get("idToken")
            .and_then(|v| v.as_str())
            .ok_or("Codex 会话缺少 id token。")?;
        // Codex refreshes a ChatGPT session based on these three values. The
        // account id is optional in the CLI auth format and intentionally is
        // not guessed from a different local account.
        let auth = serde_json::json!({
            "auth_mode": "chatgpt",
            "OPENAI_API_KEY": serde_json::Value::Null,
            "tokens": {"access_token": access, "refresh_token": refresh, "id_token": id, "account_id": serde_json::Value::Null},
            "last_refresh": "1970-01-01T00:00:00Z",
        });
        std::fs::write(home.join("auth.json"), auth.to_string())
            .map_err(|error| format!("无法准备 Codex 会话：{error}"))
    }

    fn write_gateway_error(
        stream: &mut TcpStream,
        requested_model: &str,
        is_stream: bool,
        now_unix: u64,
        message: &str,
    ) -> std::io::Result<bool> {
        let message = serde_json::to_string(message).unwrap_or_else(|_| "\"网关调用失败\"".into());
        let model = serde_json::to_string(requested_model).unwrap_or_else(|_| "\"unknown\"".into());
        let response = if is_stream {
            format!(
                "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\ndata: {{\"id\":\"resp_error\",\"object\":\"chat.completion.chunk\",\"created\":{now_unix},\"model\":{model},\"choices\":[{{\"index\":0,\"delta\":{{\"role\":\"assistant\",\"content\":{message}}},\"finish_reason\":null}}]}}\n\ndata: {{\"id\":\"resp_error\",\"object\":\"chat.completion.chunk\",\"created\":{now_unix},\"model\":{model},\"choices\":[{{\"index\":0,\"delta\":{{}},\"finish_reason\":\"stop\"}}]}}\n\ndata: [DONE]\n\n"
            )
        } else {
            format!(
                "HTTP/1.1 502 Bad Gateway\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n{{\"error\":{{\"message\":{message},\"type\":\"upstream_error\"}}}}"
            )
        };
        stream.write_all(response.as_bytes())?;
        stream.flush()?;
        Ok(true)
    }

    fn resolve_upstream_endpoint(model: &str) -> Result<UpstreamEndpoint, String> {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/Users/qiizo".into());
        let app_support = format!("{home}/Library/Application Support/Codexling");
        let mut lower = model.to_lowercase();

        // Hermes custom providers only accept model IDs in their configured
        // allowlist, and render that ID directly in the picker. Codexling
        // therefore publishes aliases shaped as:
        // `供应商·模型名·账号名` (without whitespace). Convert the human-readable
        // alias back to the existing `model@account` routing syntax here.
        let picker_parts: Vec<&str> = lower.split('·').map(str::trim).collect();
        if picker_parts.len() == 3 && picker_parts.iter().all(|part| !part.is_empty()) {
            let provider_label = picker_parts[0];
            if provider_label.starts_with("openai") {
                lower = format!("openai/{}@{}", picker_parts[1], picker_parts[2]);
            } else if provider_label.starts_with("google") {
                lower = format!("google/{}@{}", picker_parts[1], picker_parts[2]);
            } else if provider_label.starts_with("deepseek") {
                lower = format!("deepseek/{}@{}", picker_parts[1], picker_parts[2]);
            } else if provider_label.starts_with("opencode") {
                lower = format!("opencode/{}@{}", picker_parts[1], picker_parts[2]);
            }
        }

        let mut explicit_provider = None;
        if lower.starts_with("openai · ")
            || lower.starts_with("openai / codex · ")
            || lower.starts_with("openai/")
        {
            explicit_provider = Some("openai");
        } else if lower.starts_with("google · ")
            || lower.starts_with("google gemini · ")
            || lower.starts_with("google/")
        {
            explicit_provider = Some("google");
        } else if lower.starts_with("deepseek · ")
            || lower.starts_with("deepseek 官方 · ")
            || lower.starts_with("deepseek/")
        {
            explicit_provider = Some("deepseek");
        } else if lower.starts_with("opencode · ")
            || lower.starts_with("opencode 聚合平台 · ")
            || lower.starts_with("opencode/")
        {
            explicit_provider = Some("opencode");
        }

        for prefix in &[
            "openai · ",
            "openai / codex · ",
            "google · ",
            "google gemini · ",
            "deepseek · ",
            "deepseek 官方 · ",
            "opencode · ",
            "opencode 聚合平台 · ",
            "openai/",
            "google/",
            "deepseek/",
            "opencode/",
        ] {
            if lower.starts_with(prefix) {
                lower = lower[prefix.len()..].trim().to_string();
                break;
            }
        }

        // Support multiple account scoping syntax:
        // 1. "gemini-3.7-flash (徐金琦)"
        // 2. "[徐金琦] gemini-3.7-flash"
        // 3. "徐金琦/gemini-3.7-flash"
        let (account_filter, base_model) =
            if let (Some(l_paren), Some(r_paren)) = (lower.find('('), lower.rfind(')')) {
                if l_paren < r_paren {
                    let acc = lower[l_paren + 1..r_paren].trim();
                    let bm = lower[..l_paren].trim();
                    (Some(acc), bm)
                } else {
                    (None, lower.as_str())
                }
            } else if lower.starts_with('[') && lower.contains(']') {
                if let Some(r_bracket) = lower.find(']') {
                    let acc = lower[1..r_bracket].trim();
                    let bm = lower[r_bracket + 1..].trim();
                    (Some(acc), bm)
                } else {
                    (None, lower.as_str())
                }
            } else if let Some(slash_idx) = lower.find('/') {
                (
                    Some(lower[..slash_idx].trim()),
                    lower[slash_idx + 1..].trim(),
                )
            } else if let Some(at_idx) = lower.find('@') {
                (Some(lower[at_idx + 1..].trim()), lower[..at_idx].trim())
            } else if let Some(colon_idx) = lower.find(':') {
                (
                    Some(lower[colon_idx + 1..].trim()),
                    lower[..colon_idx].trim(),
                )
            } else {
                (None, lower.as_str())
            };

        let is_google = explicit_provider == Some("google") || base_model.contains("gemini");
        let is_openai = explicit_provider == Some("openai")
            || base_model.starts_with("gpt-")
            || base_model.starts_with("o1")
            || base_model.starts_with("o3")
            || base_model.starts_with("o4");
        let is_deepseek = explicit_provider == Some("deepseek")
            || (base_model.contains("deepseek") && !base_model.contains("opencode"));
        let is_opencode = explicit_provider == Some("opencode")
            || base_model.contains("qwen")
            || base_model.contains("kimi")
            || base_model.contains("minimax")
            || base_model.contains("glm")
            || base_model.contains("hy3")
            || base_model.contains("hy4")
            || base_model.contains("grok");

        // 1. Google Gemini 专属通道（严格隔离，只使用已登录账号的 OAuth 凭证）
        if is_google {
            let conn_path = format!("{app_support}/connections-v1.json");
            if let Ok(content) = std::fs::read_to_string(&conn_path) {
                if let Ok(registry) = serde_json::from_str::<serde_json::Value>(&content) {
                    if let Some(accounts) =
                        registry.get("geminiConnections").and_then(|a| a.as_array())
                    {
                        for acc in accounts {
                            if !acc
                                .get("isEnabled")
                                .and_then(|e| e.as_bool())
                                .unwrap_or(true)
                            {
                                continue;
                            }
                            let display_name = acc
                                .get("displayName")
                                .and_then(|d| d.as_str())
                                .unwrap_or("");
                            let email = acc.get("email").and_then(|e| e.as_str()).unwrap_or("");
                            let label = acc.get("label").and_then(|l| l.as_str()).unwrap_or("");
                            let handle = acc
                                .get("credentialHandle")
                                .and_then(|h| h.as_str())
                                .unwrap_or("");

                            let matched = match account_filter {
                                Some(filter) => Self::gateway_account_filter_matches(
                                    filter,
                                    &[display_name, email, label],
                                ),
                                None => true,
                            };

                            if matched {
                                if let Ok(access_token) =
                                    Self::gemini_oauth_access_token(&app_support, handle)
                                {
                                    let requested = base_model.trim().to_lowercase();
                                    let normalized = |value: &str| {
                                        value
                                            .trim()
                                            .trim_start_matches("models/")
                                            .trim_start_matches("MODEL_GOOGLE_")
                                            .trim_start_matches("MODEL_OPENAI_")
                                            .to_lowercase()
                                            .replace('_', "-")
                                    };
                                    let target_model = acc
                                        .get("availableModelIDs")
                                        .and_then(|models| models.as_array())
                                        .and_then(|models| models.iter().filter_map(|model| model.as_str()).find(|candidate| {
                                            candidate.eq_ignore_ascii_case(base_model)
                                                || candidate.strip_suffix("-tiered").map(|alias| alias.eq_ignore_ascii_case(base_model)).unwrap_or(false)
                                                || normalized(candidate) == requested
                                        }))
                                        .map(str::to_owned)
                                        .ok_or_else(|| format!("Google OAuth 账号不提供模型 [{base_model}]，未执行回退。"))?;
                                    return Ok(UpstreamEndpoint {
                                        url: "https://daily-cloudcode-pa.googleapis.com/v1internal:generateContent".into(),
                                        auth_header: format!("Bearer {access_token}"),
                                        // The Cloud Code envelope carries this project directly.
                                        // x-goog-user-project would instead require Service Usage
                                        // IAM on Google's companion project.
                                        extra_headers: Vec::new(),
                                        project: acc
                                            .get("projectId")
                                            .and_then(|project| project.as_str())
                                            .filter(|project| !project.trim().is_empty())
                                            .map(str::to_owned),
                                        target_model,
                                        provider_name: "Google Gemini".into(),
                                        _account_name: if !display_name.is_empty() { display_name.to_string() } else { email.to_string() },
                                        codex_home: None,
                                    });
                                }
                            }
                        }
                    }
                }
            }
            return Err(format!("Google Gemini 账号 [{}] 的 OAuth 凭证不可用，请在 Codexling 重新登录该 Google 账号后重试。", account_filter.unwrap_or("默认")));
        }

        // 2. OpenAI / Codex 专属通道 (严格隔离，绝不降级)
        if is_openai {
            let conn_path = format!("{app_support}/connections-v1.json");
            if let Ok(content) = std::fs::read_to_string(&conn_path) {
                if let Ok(registry) = serde_json::from_str::<serde_json::Value>(&content) {
                    if let Some(accounts) = registry.get("codexAccounts").and_then(|a| a.as_array())
                    {
                        for account in accounts {
                            if !account
                                .get("isEnabled")
                                .and_then(|e| e.as_bool())
                                .unwrap_or(true)
                                || account.get("authenticationState").and_then(|s| s.as_str())
                                    != Some("connected")
                            {
                                continue;
                            }
                            let label = account
                                .get("label")
                                .and_then(|v| v.as_str())
                                .unwrap_or("codex");
                            let display = account
                                .get("usage")
                                .and_then(|u| u.get("accountName"))
                                .and_then(|v| v.as_str())
                                .unwrap_or(label);
                            let slug = Self::friendly_account_slug(Some(display), None, label)
                                .0
                                .to_lowercase();
                            if let Some(filter) = account_filter {
                                if filter.replace('-', "") != slug.replace('-', "") {
                                    continue;
                                }
                            }
                            let relative_home = account
                                .get("relativeHomeDirectory")
                                .and_then(|v| v.as_str())
                                .unwrap_or("");
                            if relative_home.contains('/') || relative_home.contains("..") {
                                continue;
                            }
                            let codex_home =
                                format!("{app_support}/Runtimes/Codex/{relative_home}");
                            if std::path::Path::new(&codex_home)
                                .join("oauth_token.json")
                                .is_file()
                            {
                                return Ok(UpstreamEndpoint {
                                    url: String::new(),
                                    auth_header: String::new(),
                                    extra_headers: vec![],
                                    project: None,
                                    target_model: if base_model.is_empty() {
                                        "gpt-5.6".into()
                                    } else {
                                        base_model.to_string()
                                    },
                                    provider_name: "OpenAI / Codex".into(),
                                    _account_name: display.into(),
                                    codex_home: Some(codex_home),
                                });
                            }
                        }
                    }
                }
            }
            return Err("OpenAI / Codex 会话未就绪，请在 Codexling 中检查登录状态。".into());
        }

        // 3. DeepSeek 官方直连 (严格隔离，仅选 DeepSeek 时调用)
        if is_deepseek {
            let conn_path = format!("{app_support}/connections-v1.json");
            let mut selected_handle = None;
            if let Ok(content) = std::fs::read_to_string(&conn_path) {
                if let Ok(registry) = serde_json::from_str::<serde_json::Value>(&content) {
                    if let Some(accounts) = registry
                        .get("deepSeekConnections")
                        .and_then(|a| a.as_array())
                    {
                        for account in accounts {
                            if !account
                                .get("isEnabled")
                                .and_then(|e| e.as_bool())
                                .unwrap_or(true)
                                || account.get("authenticationState").and_then(|s| s.as_str())
                                    != Some("connected")
                            {
                                continue;
                            }
                            let label = account.get("label").and_then(|v| v.as_str()).unwrap_or("");
                            let slug = Self::friendly_account_slug(Some(label), None, label)
                                .0
                                .to_lowercase();
                            let matched = account_filter.map_or(true, |filter| {
                                filter.replace('-', "") == slug.replace('-', "")
                            });
                            if matched {
                                selected_handle = account
                                    .get("credentialHandle")
                                    .and_then(|v| v.as_str())
                                    .map(str::to_string);
                                break;
                            }
                        }
                    }
                }
            }
            if account_filter.is_some() && selected_handle.is_none() {
                return Err(format!(
                    "DeepSeek 账号 [{}] 未启用或认证未就绪；已阻止回退。",
                    account_filter.unwrap()
                ));
            }
            let key_dir = format!("{app_support}/deepseek_credentials");
            if let Ok(entries) = std::fs::read_dir(&key_dir) {
                for entry in entries.flatten() {
                    if let Some(handle) = selected_handle.as_deref() {
                        let file_name = entry.file_name();
                        let name = file_name.to_string_lossy();
                        if name != format!("{handle}.key") && name != format!("{handle}.json") {
                            continue;
                        }
                    }
                    if let Ok(content) = std::fs::read_to_string(entry.path()) {
                        let key = content.trim().to_string();
                        if !key.is_empty() {
                            let actual_model = if base_model.contains("reason")
                                || base_model.contains("r1")
                                || base_model.contains("o1")
                                || base_model.contains("thinking")
                            {
                                "deepseek-reasoner"
                            } else {
                                "deepseek-chat"
                            };
                            return Ok(UpstreamEndpoint {
                                url: "https://api.deepseek.com/chat/completions".into(),
                                auth_header: format!("Bearer {key}"),
                                extra_headers: vec![],
                                project: None,
                                target_model: actual_model.to_string(),
                                provider_name: "DeepSeek 官方".into(),
                                _account_name: "DeepSeek Harness".into(),
                                codex_home: None,
                            });
                        }
                    }
                }
            }
            return Err("DeepSeek API Key 未配置，已阻止降级以保护余额。".into());
        }

        // 4. OpenCode 聚合平台 (严格隔离)
        if is_opencode {
            let conn_path = format!("{app_support}/connections-v1.json");
            let mut selected_handle = None;
            if let Ok(content) = std::fs::read_to_string(&conn_path) {
                if let Ok(registry) = serde_json::from_str::<serde_json::Value>(&content) {
                    if let Some(accounts) = registry
                        .get("openCodeConnections")
                        .and_then(|a| a.as_array())
                    {
                        for account in accounts {
                            if !account
                                .get("isEnabled")
                                .and_then(|e| e.as_bool())
                                .unwrap_or(true)
                                || account.get("authenticationState").and_then(|s| s.as_str())
                                    != Some("connected")
                            {
                                continue;
                            }
                            let label = account.get("label").and_then(|v| v.as_str()).unwrap_or("");
                            let slug = Self::friendly_account_slug(Some(label), None, label)
                                .0
                                .to_lowercase();
                            let matched = account_filter.map_or(true, |filter| {
                                filter.replace('-', "") == slug.replace('-', "")
                            });
                            if matched {
                                selected_handle = account
                                    .get("credentialHandle")
                                    .and_then(|v| v.as_str())
                                    .map(str::to_string);
                                break;
                            }
                        }
                    }
                }
            }
            if account_filter.is_some() && selected_handle.is_none() {
                return Err(format!(
                    "OpenCode 账号 [{}] 未启用或认证未就绪；已阻止回退。",
                    account_filter.unwrap()
                ));
            }
            let key_dir = format!("{app_support}/opencode_credentials");
            if let Ok(entries) = std::fs::read_dir(&key_dir) {
                for entry in entries.flatten() {
                    if let Some(handle) = selected_handle.as_deref() {
                        let file_name = entry.file_name();
                        let name = file_name.to_string_lossy();
                        if name != format!("{handle}.key") && name != format!("{handle}.json") {
                            continue;
                        }
                    }
                    if let Ok(content) = std::fs::read_to_string(entry.path()) {
                        let key = content.trim().to_string();
                        if !key.is_empty() {
                            return Ok(UpstreamEndpoint {
                                url: "https://opencode.ai/zen/go/v1/chat/completions".into(),
                                auth_header: format!("Bearer {key}"),
                                extra_headers: vec![],
                                project: None,
                                target_model: base_model.to_string(),
                                provider_name: "OpenCode 聚合平台".into(),
                                _account_name: "OpenCode".into(),
                                codex_home: None,
                            });
                        }
                    }
                }
            }
            return Err("OpenCode API Key 未配置。".into());
        }

        Err(format!(
            "无法识别该模型的目标供应商 [{}]，已阻止跨供应商降级以保护余额。",
            model
        ))
    }

    /// Loads the user-owned Gemini OAuth session and refreshes it when a
    /// refresh token exists. Gemini traffic is OAuth-only.
    fn gemini_oauth_access_token(app_support: &str, handle: &str) -> Result<String, String> {
        if handle.trim().is_empty() {
            return Err("Google OAuth credential handle is missing".into());
        }
        let path = format!("{app_support}/gemini_oauth/{handle}.json");
        let raw = std::fs::read_to_string(&path)
            .map_err(|_| "Google OAuth token is missing; sign in again".to_string())?;
        let token: serde_json::Value = serde_json::from_str(&raw)
            .map_err(|_| "Google OAuth token file is invalid; sign in again".to_string())?;
        let existing_access = token
            .get("accessToken")
            .and_then(|value| value.as_str())
            .filter(|value| !value.trim().is_empty())
            .map(str::to_owned);
        // Do not refresh a still-valid access token for every routed request.
        // Some user-owned legacy OAuth clients require a secret only during
        // refresh.  The native App can continue using its valid access token,
        // and the Gateway must do the same until it is actually near expiry.
        if existing_access.is_some() && Self::gemini_access_token_is_fresh(&token) {
            return Ok(existing_access.expect("checked is_some"));
        }
        let refresh_token = token
            .get("refreshToken")
            .and_then(|value| value.as_str())
            .filter(|value| !value.trim().is_empty());

        let Some(refresh_token) = refresh_token else {
            return existing_access
                .ok_or_else(|| "Google OAuth access token is missing; sign in again".into());
        };
        let client_id = token
            .get("clientID")
            .and_then(|value| value.as_str())
            .map(str::to_owned)
            .or_else(|| std::env::var("CODEXLING_GEMINI_OAUTH_CLIENT_ID").ok())
            .filter(|value| !value.trim().is_empty());
        let Some(client_id) = client_id else {
            return existing_access.ok_or_else(|| {
                "Gemini OAuth client configuration is missing; restart Codexling".into()
            });
        };

        let output = std::process::Command::new("curl")
            .arg("-s")
            .arg("-X")
            .arg("POST")
            .arg("https://oauth2.googleapis.com/token")
            .arg("-d")
            .arg("grant_type=refresh_token")
            .arg("-d")
            .arg(format!("client_id={client_id}"))
            .arg("-d")
            .arg(format!("refresh_token={refresh_token}"))
            .output()
            .map_err(|_| "Unable to refresh Google OAuth token".to_string())?;
        let refreshed: serde_json::Value = serde_json::from_slice(&output.stdout)
            .map_err(|_| "Google OAuth token refresh returned an invalid response".to_string())?;
        refreshed
            .get("access_token")
            .and_then(|value| value.as_str())
            .filter(|value| !value.trim().is_empty())
            .map(str::to_owned)
            .or(existing_access)
            .ok_or_else(|| "Google OAuth token refresh failed; sign in again".into())
    }

    fn gemini_access_token_is_fresh(token: &serde_json::Value) -> bool {
        let Some(expires_at) = token.get("expiresAt").and_then(|value| value.as_str()) else {
            return false;
        };
        let Some(expires_unix) = Self::parse_rfc3339_utc(expires_at) else {
            return false;
        };
        let now_unix = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|duration| duration.as_secs() as i64)
            .unwrap_or(i64::MAX);
        // Match the App's 60-second safety window.
        expires_unix.saturating_sub(now_unix) >= 60
    }

    /// Minimal RFC3339 UTC parser for Swift's persisted ISO-8601 `expiresAt`.
    /// It accepts both `YYYY-MM-DDTHH:MM:SSZ` and fractional-second variants.
    fn parse_rfc3339_utc(value: &str) -> Option<i64> {
        let core = value.strip_suffix('Z')?.split('.').next()?;
        let bytes = core.as_bytes();
        if bytes.len() != 19
            || bytes[4] != b'-'
            || bytes[7] != b'-'
            || bytes[10] != b'T'
            || bytes[13] != b':'
            || bytes[16] != b':'
        {
            return None;
        }
        let number = |range: std::ops::Range<usize>| {
            std::str::from_utf8(&bytes[range]).ok()?.parse::<i64>().ok()
        };
        let (year, month, day, hour, minute, second) = (
            number(0..4)?,
            number(5..7)?,
            number(8..10)?,
            number(11..13)?,
            number(14..16)?,
            number(17..19)?,
        );
        if !(1..=12).contains(&month)
            || !(1..=31).contains(&day)
            || hour > 23
            || minute > 59
            || second > 60
        {
            return None;
        }
        // Howard Hinnant's civil-date conversion, days since Unix epoch.
        let adjusted_year = year - i64::from(month <= 2);
        let era = if adjusted_year >= 0 {
            adjusted_year
        } else {
            adjusted_year - 399
        } / 400;
        let yoe = adjusted_year - era * 400;
        let shifted_month = month + if month > 2 { -3 } else { 9 };
        let doy = (153 * shifted_month + 2) / 5 + day - 1;
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
        let days = era * 146_097 + doe - 719_468;
        Some(days * 86_400 + hour * 3_600 + minute * 60 + second)
    }

    fn has_gemini_oauth_token_for_home(home: &str, handle: &str) -> bool {
        if handle.trim().is_empty() {
            return false;
        }
        let path =
            format!("{home}/Library/Application Support/Codexling/gemini_oauth/{handle}.json");
        std::fs::read_to_string(path)
            .ok()
            .and_then(|raw| serde_json::from_str::<serde_json::Value>(&raw).ok())
            .and_then(|token| {
                token
                    .get("accessToken")
                    .and_then(|value| value.as_str())
                    .map(str::to_owned)
            })
            .is_some_and(|token| !token.trim().is_empty())
    }

    /// Scoped Gateway ids use a URL-safe account slug (for example
    /// `xujinqixujinqi-gmail-com`), while the registry keeps the original
    /// email address.  Match both representations without treating dashes,
    /// dots or `@` as meaningful separators.
    fn gateway_account_filter_matches(filter: &str, candidates: &[&str]) -> bool {
        let normalize = |value: &str| {
            value
                .chars()
                .map(|character| {
                    if character.is_ascii_alphanumeric() {
                        character.to_ascii_lowercase()
                    } else {
                        ' '
                    }
                })
                .collect::<String>()
                .split_whitespace()
                .collect::<Vec<_>>()
                .join(" ")
        };
        let normalized_filter = normalize(filter);
        if normalized_filter.is_empty() {
            return false;
        }
        let compact_filter = normalized_filter.replace(' ', "");
        candidates.iter().any(|candidate| {
            let normalized_candidate = normalize(candidate);
            if normalized_candidate.is_empty() {
                return false;
            }
            let compact_candidate = normalized_candidate.replace(' ', "");
            normalized_candidate.contains(&normalized_filter)
                || normalized_filter.contains(&normalized_candidate)
                || compact_candidate == compact_filter
        })
    }

    fn friendly_account_slug(
        display_name: Option<&str>,
        _email: Option<&str>,
        label: &str,
    ) -> (String, String) {
        let raw_name = if let Some(d) = display_name {
            let trimmed = d.trim();
            if !trimmed.is_empty() && !trimmed.contains('@') {
                trimmed.to_string()
            } else {
                label.trim().to_string()
            }
        } else {
            label.trim().to_string()
        };

        let clean_name = if raw_name.contains('@') {
            raw_name.split('@').next().unwrap_or(&raw_name).to_string()
        } else {
            raw_name
        };

        // Title Case words in slug for consistent UI display (e.g. Seven-X, X-Seven, DeepSeek)
        let parts: Vec<String> = clean_name
            .split(|c: char| c.is_whitespace() || c == '-' || c == '_' || c == '.')
            .filter(|s| !s.is_empty())
            .map(|s| {
                if s.eq_ignore_ascii_case("deepseek") {
                    "DeepSeek".to_string()
                } else if s.eq_ignore_ascii_case("opencode") {
                    "OpenCode".to_string()
                } else if s.len() <= 3 && s.chars().all(|c| c.is_ascii_alphabetic()) {
                    s.to_uppercase()
                } else {
                    let mut c = s.chars();
                    match c.next() {
                        None => String::new(),
                        Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
                    }
                }
            })
            .collect();

        let slug = if parts.is_empty() {
            clean_name.clone()
        } else {
            parts.join("-")
        };

        (slug, clean_name)
    }

    /// `/v1/models` IDs are protocol values, not display labels. Keep them
    /// whitespace-free so clients such as Hermes can switch to them, while
    /// `name`/`display_name` retain the friendly provider and account copy.
    fn scoped_model_id(provider: &str, model: &str, account_slug: &str) -> String {
        format!("{provider}/{model}@{account_slug}")
    }

    /// Cloud Code uses a routing suffix for tiered models. Keep it in the
    /// protocol ID, but show the product name users recognize.
    fn google_model_display_name(model: &str) -> String {
        match model {
            "gemini-3.7-flash-tiered" => "Gemini 3.7 Flash".into(),
            _ => model.replace('-', " "),
        }
    }

    fn get_dynamic_models_payload() -> serde_json::Value {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/Users/qiizo".into());
        Self::get_dynamic_models_payload_for_home(&home)
    }

    fn get_dynamic_models_payload_for_home(home: &str) -> serde_json::Value {
        let mut models = Vec::new();
        let conn_path = format!("{home}/Library/Application Support/Codexling/connections-v1.json");
        if let Ok(content) = std::fs::read_to_string(&conn_path) {
            if let Ok(registry) = serde_json::from_str::<serde_json::Value>(&content) {
                // 1. Group 1: OpenAI / Codex Accounts
                if let Some(accounts) = registry.get("codexAccounts").and_then(|a| a.as_array()) {
                    for acc in accounts {
                        if !acc
                            .get("isEnabled")
                            .and_then(|e| e.as_bool())
                            .unwrap_or(true)
                            || acc.get("authenticationState").and_then(|s| s.as_str())
                                != Some("connected")
                        {
                            continue;
                        }
                        let label = acc.get("label").and_then(|l| l.as_str()).unwrap_or("codex");
                        let account_name = acc
                            .get("usage")
                            .and_then(|u| u.get("accountName"))
                            .and_then(|n| n.as_str());
                        let email = acc
                            .get("usage")
                            .and_then(|u| u.get("accountEmail"))
                            .and_then(|e| e.as_str());
                        let plan_raw = acc
                            .get("usage")
                            .and_then(|u| u.get("planName"))
                            .and_then(|p| p.as_str())
                            .unwrap_or("Plus");
                        let plan = if plan_raw.eq_ignore_ascii_case("plus") {
                            "Plus"
                        } else if plan_raw.eq_ignore_ascii_case("free") {
                            "Free"
                        } else {
                            plan_raw
                        };
                        let remaining = acc
                            .get("usage")
                            .and_then(|u| u.get("shortWindow"))
                            .and_then(|w| w.get("remaining"))
                            .and_then(|r| r.as_i64())
                            .unwrap_or(100);
                        let coupons = acc
                            .get("usage")
                            .and_then(|u| u.get("resetCoupons"))
                            .and_then(|c| c.as_array())
                            .map(|a| a.len())
                            .unwrap_or(0);
                        let quota_desc = if coupons > 0 {
                            format!("额度: {}% (含{}张重置券)", remaining, coupons)
                        } else {
                            format!("额度: {}%", remaining)
                        };

                        let (slug, friendly_name) =
                            Self::friendly_account_slug(account_name, email, label);

                        let primary_scoped = vec![
                            "gpt-5.6",
                            "gpt-5.6-thinking",
                            "gpt-5.6-sol",
                            "gpt-5.6-terra",
                            "gpt-5.6-luna",
                            "gpt-5.6-mini",
                            "gpt-5.5",
                            "gpt-5",
                            "o3-mini",
                        ];
                        for mid in primary_scoped {
                            let sid = Self::scoped_model_id("openai", mid, &slug);
                            if !models.iter().any(|m: &serde_json::Value| m["id"] == sid) {
                                let variant_note = if mid.ends_with("-sol") {
                                    " · Sol 太阳版"
                                } else if mid.ends_with("-terra") {
                                    " · Terra 地球版"
                                } else if mid.ends_with("-luna") {
                                    " · Luna 月亮版"
                                } else if mid == "gpt-5.6-mini" {
                                    " · Mini 轻量版"
                                } else if mid.ends_with("-thinking") {
                                    " · Thinking 深度思考"
                                } else {
                                    ""
                                };
                                models.push(serde_json::json!({
                                    "id": sid,
                                    "name": format!("OpenAI · {mid} ({friendly_name})"),
                                    "display_name": format!("OpenAI · {mid} ({friendly_name})"),
                                    "object": "model",
                                    "created": 1700000000,
                                    "provider": "OpenAI / Codex",
                                    "owned_by": "openai",
                                    "account": friendly_name,
                                    "permission_tier": plan,
                                    "quota_remaining": quota_desc,
                                    "description": format!("OpenAI {}{} [账号: {} · {} | {}]", mid, variant_note, friendly_name, plan, quota_desc)
                                }));
                            }
                        }

                        // The account's discovered catalog is authoritative for
                        // its exported model list; it is scoped to this account.
                        if true {
                            if let Some(mids) =
                                acc.get("availableModelIDs").and_then(|m| m.as_array())
                            {
                                for m in mids {
                                    if let Some(raw_mid) = m.as_str() {
                                        let mut clean_mid = raw_mid.to_string();
                                        if clean_mid.ends_with("-wm") {
                                            clean_mid =
                                                clean_mid[..clean_mid.len() - 3].to_string();
                                        }
                                        clean_mid = clean_mid
                                            .replace("gpt-5-6", "gpt-5.6")
                                            .replace("gpt-5-5", "gpt-5.5")
                                            .replace("gpt-5-4", "gpt-5.4")
                                            .replace("gpt-5-3", "gpt-5.3");

                                        if clean_mid == "auto"
                                            || clean_mid == "research"
                                            || clean_mid.contains("-instant")
                                        {
                                            continue;
                                        }
                                        if clean_mid.chars().any(char::is_whitespace) {
                                            continue;
                                        }
                                        let sid =
                                            Self::scoped_model_id("openai", &clean_mid, &slug);
                                        if !models.iter().any(|existing| existing["id"] == sid) {
                                            models.push(serde_json::json!({
                                            "id": sid,
                                            "name": format!("OpenAI · {clean_mid} ({friendly_name})"),
                                            "display_name": format!("OpenAI · {clean_mid} ({friendly_name})"),
                                            "object": "model",
                                            "created": 1700000000,
                                            "provider": "OpenAI / Codex",
                                            "owned_by": "openai",
                                            "account": friendly_name,
                                            "permission_tier": plan,
                                            "quota_remaining": quota_desc,
                                            "description": format!("OpenAI {} [账号: {} · {} | {}]", clean_mid, friendly_name, plan, quota_desc)
                                        }));
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // 2. Group 2: Google Gemini Accounts (OAuth token + proxy enabled)
                if let Some(accounts) = registry.get("geminiConnections").and_then(|a| a.as_array())
                {
                    for acc in accounts {
                        let is_enabled = acc
                            .get("isEnabled")
                            .and_then(|e| e.as_bool())
                            .unwrap_or(true);
                        let handle = acc
                            .get("credentialHandle")
                            .and_then(|h| h.as_str())
                            .unwrap_or("");
                        let has_oauth_token = Self::has_gemini_oauth_token_for_home(&home, handle);

                        if !is_enabled
                            || !has_oauth_token
                            || acc.get("authenticationState").and_then(|s| s.as_str())
                                != Some("connected")
                        {
                            continue;
                        }
                        let label = acc
                            .get("label")
                            .and_then(|l| l.as_str())
                            .unwrap_or("gemini");
                        let display_name = acc.get("displayName").and_then(|d| d.as_str());
                        let email = acc.get("email").and_then(|e| e.as_str());
                        let tier = acc
                            .get("tier")
                            .and_then(|t| t.as_str())
                            .unwrap_or("Google OAuth");
                        let five_hour = acc
                            .get("geminiFiveHourRemaining")
                            .and_then(|f| f.as_f64())
                            .unwrap_or(1.0);
                        let weekly = acc
                            .get("geminiWeeklyRemaining")
                            .and_then(|w| w.as_f64())
                            .unwrap_or(1.0);
                        let quota_desc =
                            if (five_hour - 1.0).abs() < 0.001 && (weekly - 1.0).abs() < 0.001 {
                                "5h 配额充足".to_string()
                            } else {
                                format!("5h: {:.0}%, 周: {:.0}%", five_hour * 100.0, weekly * 100.0)
                            };

                        let (slug, friendly_name) =
                            Self::friendly_account_slug(display_name, email, label);

                        let model_ids = acc
                            .get("availableModelIDs")
                            .and_then(|models| models.as_array())
                            .cloned()
                            .unwrap_or_default();
                        for raw_mid in model_ids {
                            let Some(mid) = raw_mid.as_str() else {
                                continue;
                            };
                            if mid.trim().is_empty() || mid.chars().any(char::is_whitespace) {
                                continue;
                            }
                            let sid = Self::scoped_model_id("google", mid, &slug);
                            let display_model = Self::google_model_display_name(mid);
                            if !models.iter().any(|m: &serde_json::Value| m["id"] == sid) {
                                models.push(serde_json::json!({
                                    "id": sid,
                                    "name": format!("Google · {display_model} ({friendly_name})"),
                                    "display_name": format!("Google · {display_model} ({friendly_name})"),
                                    "object": "model",
                                    "created": 1700000000,
                                    "provider": "Google Gemini",
                                    "owned_by": "google",
                                    "account": friendly_name,
                                    "permission_tier": tier,
                                    "quota_remaining": quota_desc,
                                    "description": format!("Google {} [账号: {} · {} | 配额: {}]", mid, friendly_name, tier, quota_desc)
                                }));
                            }
                        }
                    }
                }

                // 3. Group 3: DeepSeek 官方账号
                if let Some(accounts) = registry
                    .get("deepSeekConnections")
                    .and_then(|a| a.as_array())
                {
                    for acc in accounts {
                        if !acc
                            .get("isEnabled")
                            .and_then(|e| e.as_bool())
                            .unwrap_or(true)
                            || acc.get("authenticationState").and_then(|s| s.as_str())
                                != Some("connected")
                        {
                            continue;
                        }
                        let label = acc
                            .get("label")
                            .and_then(|l| l.as_str())
                            .unwrap_or("deepseek");
                        let balance_val = acc
                            .get("balance")
                            .and_then(|b| b.get("total"))
                            .and_then(|t| t.as_f64())
                            .unwrap_or(0.0);
                        let balance_desc = format!("¥{:.2}", balance_val);
                        let (slug, friendly_name) = Self::friendly_account_slug(None, None, label);

                        let primary_scoped =
                            vec!["deepseek-chat", "deepseek-reasoner", "deepseek-v4-pro"];
                        for mid in primary_scoped {
                            let sid = Self::scoped_model_id("deepseek", mid, &slug);
                            if !models.iter().any(|m: &serde_json::Value| m["id"] == sid) {
                                models.push(serde_json::json!({
                                    "id": sid,
                                    "name": format!("DeepSeek · {mid} ({friendly_name})"),
                                    "display_name": format!("DeepSeek · {mid} ({friendly_name})"),
                                    "object": "model",
                                    "created": 1700000000,
                                    "provider": "DeepSeek 官方",
                                    "owned_by": "deepseek",
                                    "account": friendly_name,
                                    "permission_tier": "官方直连",
                                    "quota_remaining": balance_desc,
                                    "description": format!("DeepSeek {} [账号: {} · 官方直连 | 余额: {}]", mid, friendly_name, balance_desc)
                                }));
                            }
                        }
                    }
                }

                // 4. Group 4: OpenCode 聚合平台
                if let Some(accounts) = registry
                    .get("openCodeConnections")
                    .and_then(|a| a.as_array())
                {
                    for acc in accounts {
                        if !acc
                            .get("isEnabled")
                            .and_then(|e| e.as_bool())
                            .unwrap_or(true)
                            || acc.get("authenticationState").and_then(|s| s.as_str())
                                != Some("connected")
                        {
                            continue;
                        }
                        let label = acc
                            .get("label")
                            .and_then(|l| l.as_str())
                            .unwrap_or("opencode");
                        let plan = acc
                            .get("plan")
                            .and_then(|p| p.as_str())
                            .unwrap_or("go")
                            .to_uppercase();
                        let (slug, friendly_name) = Self::friendly_account_slug(None, None, label);

                        if let Some(avail_models) =
                            acc.get("availableModelIDs").and_then(|m| m.as_array())
                        {
                            let count = avail_models.len();
                            let quota_desc = format!("可用 ({} 款模型)", count);
                            for raw_m in avail_models {
                                if let Some(mid) = raw_m.as_str() {
                                    if mid.chars().any(char::is_whitespace) {
                                        continue;
                                    }
                                    let sid = Self::scoped_model_id("opencode", mid, &slug);
                                    if !models.iter().any(|m: &serde_json::Value| m["id"] == sid) {
                                        models.push(serde_json::json!({
                                            "id": sid,
                                            "name": format!("OpenCode · {mid} ({friendly_name})"),
                                            "display_name": format!("OpenCode · {mid} ({friendly_name})"),
                                            "object": "model",
                                            "created": 1700000000,
                                            "provider": "OpenCode 聚合平台",
                                            "owned_by": "opencode",
                                            "account": friendly_name,
                                            "permission_tier": format!("OpenCode {plan}"),
                                            "quota_remaining": quota_desc,
                                            "description": format!("OpenCode {} [账号: {} · {} | 状态: {}]", mid, friendly_name, plan, quota_desc)
                                        }));
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        serde_json::json!({
            "object": "list",
            "data": models
        })
    }

    fn process_chat_completions(&self, body: &str) -> Vec<u8> {
        let raw_req: OpenAiChatRequest = match serde_json::from_str(body) {
            Ok(r) => r,
            Err(err) => {
                return Self::response(
                    "400 Bad Request",
                    "application/json",
                    &serde_json::json!({"error": err.to_string()}).to_string(),
                );
            }
        };

        let req_id = format!(
            "req_{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_millis()
        );
        let canonical_res = decode_chat_request(raw_req, &req_id);
        let canonical = canonical_res.value;
        self.total_requests.fetch_add(1, Ordering::Relaxed);
        self.total_input_tokens
            .fetch_add((body.len() / 4).max(1), Ordering::Relaxed);
        self.total_output_tokens.fetch_add(12, Ordering::Relaxed);

        // Resolve target via RouteTable
        let resolved = match self.route_table.resolve(&canonical.model, None) {
            Ok(t) => t,
            Err(e) => {
                return Self::response(
                    "502 Bad Gateway",
                    "application/json",
                    &serde_json::json!({"error": e.to_string()}).to_string(),
                );
            }
        };

        let resp_id = format!("resp_{req_id}");
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        if !canonical.stream {
            let resp_json = serde_json::json!({
                "id": resp_id,
                "object": "chat.completion",
                "created": now,
                "model": resolved.model,
                "choices": [
                    {
                        "index": 0,
                        "message": {
                            "role": "assistant",
                            "content": format!("Hello from Codexling Gateway! (Routed to {})", resolved.model)
                        },
                        "finish_reason": "stop"
                    }
                ],
                "usage": {
                    "prompt_tokens": (body.len() / 4).max(1),
                    "completion_tokens": 12,
                    "total_tokens": (body.len() / 4).max(1) + 12
                }
            });
            return Self::response("200 OK", "application/json", &resp_json.to_string());
        }

        // Synthesize standard streaming response events
        let events = vec![
            StreamEvent::ResponseStarted(ResponseStarted {
                sequence: 1,
                response_id: resp_id.clone(),
                model: resolved.model.clone(),
                created_at: now,
            }),
            StreamEvent::TextDelta(TextDelta {
                sequence: 2,
                item_id: format!("{resp_id}_item_0"),
                text: "Hello from Codexling Gateway!".into(),
            }),
            StreamEvent::ResponseCompleted(ResponseCompleted {
                sequence: 3,
                finish_reason: FinishReason::Stop,
            }),
        ];

        let mut sse_body = String::new();
        for ev in &events {
            let lines = encode_chat_stream_event(ev, &resp_id, &resolved.model, now);
            for line in lines {
                sse_body.push_str(&line);
            }
        }

        Self::response("200 OK", "text/event-stream", &sse_body)
    }

    fn process_responses(&self, body: &str) -> Vec<u8> {
        let raw_req: OpenAiResponsesRequest = match serde_json::from_str(body) {
            Ok(r) => r,
            Err(err) => {
                return Self::response(
                    "400 Bad Request",
                    "application/json",
                    &serde_json::json!({"error": err.to_string()}).to_string(),
                );
            }
        };

        let req_id = format!(
            "req_{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_millis()
        );
        let canonical_res = decode_responses_request(raw_req, &req_id);
        let canonical = canonical_res.value;
        self.total_requests.fetch_add(1, Ordering::Relaxed);
        self.total_input_tokens
            .fetch_add((body.len() / 4).max(1), Ordering::Relaxed);
        self.total_output_tokens.fetch_add(12, Ordering::Relaxed);

        // Resolve target via RouteTable
        let resolved = match self.route_table.resolve(&canonical.model, None) {
            Ok(t) => t,
            Err(e) => {
                return Self::response(
                    "502 Bad Gateway",
                    "application/json",
                    &serde_json::json!({"error": e.to_string()}).to_string(),
                );
            }
        };

        let resp_id = format!("resp_{req_id}");
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        if !canonical.stream {
            let resp_json = serde_json::json!({
                "id": resp_id,
                "object": "response",
                "created": now,
                "model": resolved.model,
                "status": "completed",
                "output": [
                    {
                        "id": format!("{resp_id}_item_0"),
                        "type": "message",
                        "role": "assistant",
                        "content": [
                            {
                                "type": "output_text",
                                "text": "Codex wire response via Codexling Gateway."
                            }
                        ]
                    }
                ],
                "usage": {
                    "input_tokens": (body.len() / 4).max(1),
                    "output_tokens": 12,
                    "total_tokens": (body.len() / 4).max(1) + 12
                }
            });
            return Self::response("200 OK", "application/json", &resp_json.to_string());
        }

        let events = vec![
            StreamEvent::ResponseStarted(ResponseStarted {
                sequence: 1,
                response_id: resp_id.clone(),
                model: resolved.model.clone(),
                created_at: now,
            }),
            StreamEvent::TextDelta(TextDelta {
                sequence: 2,
                item_id: format!("{resp_id}_item_0"),
                text: "Codex wire response via Codexling Gateway.".into(),
            }),
            StreamEvent::ResponseCompleted(ResponseCompleted {
                sequence: 3,
                finish_reason: FinishReason::Stop,
            }),
        ];

        let mut sse_body = String::new();
        for ev in &events {
            let lines = encode_responses_stream_event(ev, &resp_id, &resolved.model);
            for line in lines {
                sse_body.push_str(&line);
            }
        }

        Self::response("200 OK", "text/event-stream", &sse_body)
    }

    fn process_anthropic_messages(&self, body: &str) -> Vec<u8> {
        let raw_req: AnthropicMessagesRequest = match serde_json::from_str(body) {
            Ok(r) => r,
            Err(err) => {
                return Self::response(
                    "400 Bad Request",
                    "application/json",
                    &serde_json::json!({"error": err.to_string()}).to_string(),
                );
            }
        };

        let req_id = format!(
            "req_{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_millis()
        );
        let canonical_res = decode_anthropic_request(raw_req, &req_id);
        let canonical = canonical_res.value;
        self.total_requests.fetch_add(1, Ordering::Relaxed);
        self.total_input_tokens
            .fetch_add((body.len() / 4).max(1), Ordering::Relaxed);
        self.total_output_tokens.fetch_add(12, Ordering::Relaxed);

        // Resolve target via RouteTable
        let resolved = match self.route_table.resolve(&canonical.model, None) {
            Ok(t) => t,
            Err(e) => {
                return Self::response(
                    "502 Bad Gateway",
                    "application/json",
                    &serde_json::json!({"error": e.to_string()}).to_string(),
                );
            }
        };

        let resp_id = format!("msg_{req_id}");

        if !canonical.stream {
            let resp_json = serde_json::json!({
                "id": resp_id,
                "type": "message",
                "role": "assistant",
                "model": resolved.model,
                "content": [
                    {
                        "type": "text",
                        "text": "Claude Code message via Codexling Gateway."
                    }
                ],
                "stop_reason": "end_turn",
                "stop_sequence": null,
                "usage": {
                    "input_tokens": (body.len() / 4).max(1),
                    "output_tokens": 12
                }
            });
            return Self::response("200 OK", "application/json", &resp_json.to_string());
        }

        let events = vec![
            StreamEvent::ResponseStarted(ResponseStarted {
                sequence: 1,
                response_id: resp_id.clone(),
                model: resolved.model.clone(),
                created_at: std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_secs(),
            }),
            StreamEvent::TextDelta(TextDelta {
                sequence: 2,
                item_id: format!("{resp_id}_block_0"),
                text: "Claude Code message via Codexling Gateway.".into(),
            }),
            StreamEvent::ResponseCompleted(ResponseCompleted {
                sequence: 3,
                finish_reason: FinishReason::Stop,
            }),
        ];

        let mut sse_body = String::new();
        for ev in &events {
            let lines = encode_anthropic_stream_event(ev, &resp_id, &resolved.model);
            for line in lines {
                sse_body.push_str(&line);
            }
        }

        Self::response("200 OK", "text/event-stream", &sse_body)
    }

    pub fn run_loop(&self, listener: TcpListener) -> std::io::Result<()> {
        for stream_res in listener.incoming() {
            if !self.is_running.load(Ordering::Relaxed) {
                break;
            }
            if let Ok(stream) = stream_res {
                match self.handle_client(stream) {
                    Ok(true) => break,
                    Ok(false) => {}
                    Err(e) => {
                        // Client disconnects, broken pipes or connection resets should never crash the gateway daemon
                        if e.kind() != std::io::ErrorKind::BrokenPipe
                            && e.kind() != std::io::ErrorKind::ConnectionReset
                        {
                            eprintln!("[Gateway] Client error: {e}");
                        }
                    }
                }
            }
        }
        Ok(())
    }
}
