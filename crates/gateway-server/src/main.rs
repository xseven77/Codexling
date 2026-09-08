use std::io::Write;
use std::net::TcpListener;
use std::thread;
use std::time::Duration;

mod model_health;
mod server;
pub use server::{GatewayServer, GatewaySettings};

fn main() -> std::io::Result<()> {
    let mut port: u16 = 0;
    let mut token = "codexling-local-token".to_string();
    let mut auto_check = false;

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
        } else if args[i] == "--auto-check" {
            auto_check = true;
            i += 1;
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

    if auto_check {
        let health_engine = server.model_health.clone();
        thread::spawn(move || {
            let home = std::env::var("HOME").unwrap_or_else(|_| "/Users/qiizo".into());
            // Initial delay of 15 seconds after app startup before evaluating check
            thread::sleep(Duration::from_secs(15));

            // 软件启动或网关重启时：若无历史记录，执行首次引导巡检；
            // 若已有历史记录，遵从 `auto_check_on_startup_with_history` 设置
            {
                let settings = GatewaySettings::load_for_home(&home);
                let has_history = {
                    let data = match health_engine.data.lock() {
                        Ok(d) => d,
                        Err(p) => p.into_inner(),
                    };
                    data.last_full_check_at.is_some()
                };

                let should_run_startup = if !has_history {
                    true
                } else {
                    settings.auto_check_on_startup_with_history
                };

                if should_run_startup {
                    let targets = health_engine.collect_targets(&home, &model_health::CheckScope::All);
                    let count = targets.len();
                    if health_engine.try_start_job("all", count).is_ok() {
                        health_engine.run_check(&home, model_health::CheckScope::All);
                    }
                }
            }

            // 定时巡检自动化任务轮询调度（每 30 秒评估一次，比对当地小时是否命中计划）
            loop {
                thread::sleep(Duration::from_secs(30));

                let mut settings = GatewaySettings::load_for_home(&home);
                let now = model_health::ModelHealthEngine::now_epoch_secs();

                for i in 0..settings.automation_tasks.len() {
                    let is_due = GatewaySettings::is_task_due(&settings.automation_tasks[i], now);
                    if !is_due {
                        continue;
                    }
                    let (task_id, scope) = {
                        let task = &settings.automation_tasks[i];
                        let scope = model_health::CheckScope::Selective {
                            providers: task.providers.clone(),
                            account_ids: if task.all_accounts { Vec::new() } else { task.account_ids.clone() },
                            all_accounts: task.all_accounts,
                        };
                        (task.id.clone(), scope)
                    };
                    let targets = health_engine.collect_targets(&home, &scope);
                    let count = targets.len();
                    let scope_desc = format!("task:{task_id}");
                    if health_engine.try_start_job(&scope_desc, count).is_ok() {
                        settings.automation_tasks[i].last_run_at = Some(now);
                        settings.automation_tasks[i].last_run_status = Some("running".to_string());
                        let _ = settings.save_for_home(&home);

                        health_engine.run_check(&home, scope);

                        settings.automation_tasks[i].last_run_status = Some("success".to_string());
                        settings.automation_tasks[i].last_run_summary = Some(format!("完成 {} 个模型探测", count));
                        let _ = settings.save_for_home(&home);
                    }
                }
            }
        });
    }

    server.run_loop(listener)?;

    Ok(())
}
