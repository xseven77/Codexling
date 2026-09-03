pub mod server;
pub use server::GatewayServer;

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};
    use std::net::{TcpListener, TcpStream};
    use std::thread;

    fn spawn_test_server() -> (u16, String, thread::JoinHandle<()>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let token = "test-token-xyz".to_string();

        let token_clone = token.clone();
        let handle = thread::spawn(move || {
            let server = GatewayServer::new(token_clone);
            server.run_loop(listener).unwrap();
        });

        (port, token, handle)
    }

    fn send_request(port: u16, raw_http: &str) -> String {
        let mut stream = TcpStream::connect(format!("127.0.0.1:{port}")).unwrap();
        stream.write_all(raw_http.as_bytes()).unwrap();
        stream.flush().unwrap();

        let mut response = String::new();
        stream.read_to_string(&mut response).unwrap();
        response
    }

    #[test]
    fn test_server_health_and_unauthorized_status() {
        let (port, token, handle) = spawn_test_server();

        // 1. Health check is public
        let health_resp = send_request(port, "GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n");
        assert!(health_resp.contains("200 OK"));
        assert!(health_resp.contains("\"status\":\"ok\""));

        // 2. Status without token gets 401
        let unauth_resp = send_request(port, "GET /status HTTP/1.1\r\nHost: localhost\r\n\r\n");
        assert!(unauth_resp.contains("401 Unauthorized"));

        // 3. Status with valid token gets 200 OK
        let auth_req = format!("GET /status HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer {token}\r\n\r\n");
        let auth_resp = send_request(port, &auth_req);
        assert!(auth_resp.contains("200 OK"));
        assert!(auth_resp.contains("\"running\":true"));

        // Shutdown
        let shutdown_req = format!("POST /shutdown HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer {token}\r\n\r\n");
        let shutdown_resp = send_request(port, &shutdown_req);
        assert!(shutdown_resp.contains("200 OK"));

        handle.join().unwrap();
    }

    #[test]
    fn test_server_chat_rejects_legacy_fallback_alias() {
        let (port, token, handle) = spawn_test_server();

        let body = serde_json::json!({
            "model": "coding-smart",
            "messages": [{"role": "user", "content": "Hello"}],
            "stream": true
        }).to_string();

        let req = format!(
            "POST /v1/chat/completions HTTP/1.1\r\nHost: localhost\r\nContent-Length: {}\r\n\r\n{}",
            body.len(),
            body
        );

        let resp = send_request(port, &req);
        assert!(resp.contains("200 OK"));
        assert!(resp.contains("text/event-stream"));
        assert!(resp.contains("data: [DONE]"));
        assert!(resp.contains("无法识别该模型"));

        // Shutdown
        let shutdown_req = format!("POST /shutdown HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer {token}\r\n\r\n");
        send_request(port, &shutdown_req);
        handle.join().unwrap();
    }

    #[test]
    fn test_server_responses_rejects_legacy_fallback_alias() {
        let (port, token, handle) = spawn_test_server();

        let body = serde_json::json!({
            "model": "coding-fast",
            "instructions": "Refactor codebase",
            "input": [{"type": "message", "role": "user", "content": [{"type": "input_text", "text": "Fix warnings"}]}],
            "stream": true
        }).to_string();

        let req = format!(
            "POST /v1/responses HTTP/1.1\r\nHost: localhost\r\nContent-Length: {}\r\n\r\n{}",
            body.len(),
            body
        );

        let resp = send_request(port, &req);
        assert!(resp.contains("502 Bad Gateway"));
        assert!(!resp.contains("event: response.completed"));

        // Shutdown
        let shutdown_req = format!("POST /shutdown HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer {token}\r\n\r\n");
        send_request(port, &shutdown_req);
        handle.join().unwrap();
    }

    #[test]
    fn test_server_anthropic_rejects_legacy_fallback_alias() {
        let (port, token, handle) = spawn_test_server();

        let body = serde_json::json!({
            "model": "coding-smart",
            "messages": [{"role": "user", "content": "Explain Rust async"}],
            "max_tokens": 1024,
            "stream": true
        }).to_string();

        let req = format!(
            "POST /v1/messages HTTP/1.1\r\nHost: localhost\r\nContent-Length: {}\r\n\r\n{}",
            body.len(),
            body
        );

        let resp = send_request(port, &req);
        assert!(resp.contains("502 Bad Gateway"));
        assert!(!resp.contains("event: message_stop"));

        // Shutdown
        let shutdown_req = format!("POST /shutdown HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer {token}\r\n\r\n");
        send_request(port, &shutdown_req);
        handle.join().unwrap();
    }
}
