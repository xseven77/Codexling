use std::io::Write;
use std::net::TcpListener;

mod server;
pub use server::GatewayServer;

fn main() -> std::io::Result<()> {
    let mut port: u16 = 0;
    let mut token = "codexling-local-token".to_string();

    let args: Vec<String> = std::env::args().collect();
    let mut i = 1;
    while i < args.len() {
        if args[i] == "--port" && i + 1 < args.len() {
            if let Ok(p) = args[i + 1].parse::<u16>() {
                port = p;
            }
            i += 2;
        } else if args[i] == "--token" && i + 1 < args.len() {
            token = args[i + 1].clone();
            i += 2;
        } else {
            i += 1;
        }
    }

    let bind_addr = format!("127.0.0.1:{port}");
    let listener = TcpListener::bind(&bind_addr)?;
    let actual_addr = listener.local_addr()?;

    // Emit ready handshake event on first line of stdout
    println!(
        r#"{{"event":"ready","host":"127.0.0.1","port":{},"token":"{}"}}"#,
        actual_addr.port(),
        token
    );
    std::io::stdout().flush()?;

    let server = GatewayServer::new(token);
    server.run_loop(listener)?;

    Ok(())
}
