use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, OnceLock};
use regex::Regex;
use tokio::net::TcpListener;
use tokio::sync::{mpsc, Mutex, RwLock};

use crate::frb_generated::StreamSink;
use crate::ssh::{create_ssh_client, exec_command, SshClientHandler, SshConnectConfig};

#[derive(Clone, Debug)]
pub struct OpencodeConnectConfig {
    pub session_id: String,
    pub ssh_config: SshConnectConfig,
    pub remote_workdir: Option<String>,
    pub custom_opencode_path: Option<String>,
    pub preferred_local_port: Option<u16>,
}

#[derive(Clone, Debug)]
pub struct OpencodeSessionEvent {
    pub session_id: String,
    pub step: String, // "connecting", "checking", "starting_service", "pairing", "forwarding", "ready", "error", "closed", "log"
    pub message: String,
    pub local_url: Option<String>,
    pub remote_url: Option<String>,
    pub local_port: Option<u16>,
    pub remote_port: Option<u16>,
}

pub struct OpencodeSessionHandle {
    pub stop_tx: mpsc::Sender<()>,
    pub is_running: Arc<AtomicBool>,
    pub ssh_client: Arc<Mutex<russh::client::Handle<SshClientHandler>>>,
    pub remote_port: u16,
    pub local_port: u16,
    pub custom_opencode_path: Option<String>,
    pub remote_workdir: Option<String>,
}

fn active_opencode_sessions() -> &'static RwLock<HashMap<String, OpencodeSessionHandle>> {
    static SESSIONS: OnceLock<RwLock<HashMap<String, OpencodeSessionHandle>>> = OnceLock::new();
    SESSIONS.get_or_init(|| RwLock::new(HashMap::new()))
}

fn build_opencode_exec_cmd(
    subcommand: &str,
    custom_path: Option<&str>,
    workdir: Option<&str>,
) -> String {
    let mut script = String::new();
    script.push_str("export PATH=\"$HOME/.opencode/bin:$HOME/.local/bin:/usr/local/bin:$PATH\"; ");

    if let Some(dir) = workdir {
        if !dir.trim().is_empty() {
            script.push_str(&format!("cd \"{}\" 2>/dev/null || true; ", dir.trim()));
        }
    }

    if let Some(path) = custom_path {
        if !path.trim().is_empty() {
            script.push_str(&format!("\"{}\" {}; ", path.trim(), subcommand));
            return script;
        }
    }

    script.push_str(&format!(
        "OC_BIN=$(command -v opencode 2>/dev/null || echo \"$HOME/.opencode/bin/opencode\"); \"$OC_BIN\" {}; ",
        subcommand
    ));
    script
}

pub fn parse_pair_output(output: &str) -> Result<(String, u16, String), String> {
    // Regex 1: Matches standard opencode pair url http://127.0.0.1:PORT/auth/connect/TOKEN
    let re_strict = Regex::new(
        r"http://(?:127\.0\.0\.1|localhost):(?P<port>\d+)(?P<path>/auth/connect/[a-zA-Z0-9_\-]+)",
    )
    .map_err(|e| e.to_string())?;

    if let Some(caps) = re_strict.captures(output) {
        let port: u16 = caps["port"]
            .parse()
            .map_err(|_| "Failed to parse port from pair output".to_string())?;
        let path = caps["path"].to_string();
        let full_url = format!("http://127.0.0.1:{}{}", port, path);
        return Ok((full_url, port, path));
    }

    // Regex 2: Matches general http://host:port/path
    let re_general = Regex::new(r"https?://(?:[0-9a-zA-Z\.\-]+):(?P<port>\d+)(?P<path>/[^\s]*)")
        .map_err(|e| e.to_string())?;

    if let Some(caps) = re_general.captures(output) {
        let port: u16 = caps["port"]
            .parse()
            .map_err(|_| "Failed to parse port from pair output".to_string())?;
        let path = caps["path"].to_string();
        let full_url = caps.get(0).map_or("", |m| m.as_str()).to_string();
        return Ok((full_url, port, path));
    }

    // Regex 3: Matches any url
    let re_url = Regex::new(r"(?P<url>https?://[^\s]+)").map_err(|e| e.to_string())?;
    if let Some(caps) = re_url.captures(output) {
        let full_url = caps["url"].to_string();
        // default port 49374 if cannot parse
        return Ok((full_url, 49374, "/".to_string()));
    }

    Err(format!(
        "Could not find valid pair link in opencode output:\n{}",
        output
    ))
}

pub async fn start_opencode_session(
    config: OpencodeConnectConfig,
    sink: StreamSink<OpencodeSessionEvent>,
) -> Result<(), String> {
    let session_id = config.session_id.clone();

    // Check if session already exists
    {
        let sessions = active_opencode_sessions().read().await;
        if sessions.contains_key(&session_id) {
            return Err(format!("Session {} is already running", session_id));
        }
    }

    // 1. Connect to SSH
    let _ = sink.add(OpencodeSessionEvent {
        session_id: session_id.clone(),
        step: "connecting".to_string(),
        message: format!(
            "Connecting to SSH server {}@{}:{}...",
            config.ssh_config.username, config.ssh_config.host, config.ssh_config.port
        ),
        local_url: None,
        remote_url: None,
        local_port: None,
        remote_port: None,
    });

    let client = match create_ssh_client(&config.ssh_config).await {
        Ok(c) => Arc::new(Mutex::new(c)),
        Err(e) => {
            let _ = sink.add(OpencodeSessionEvent {
                session_id: session_id.clone(),
                step: "error".to_string(),
                message: format!("SSH Connection failed: {}", e),
                local_url: None,
                remote_url: None,
                local_port: None,
                remote_port: None,
            });
            return Err(e);
        }
    };

    let custom_path = config.custom_opencode_path.as_deref();
    let workdir = config.remote_workdir.as_deref();

    // 2. Check opencode service status
    let _ = sink.add(OpencodeSessionEvent {
        session_id: session_id.clone(),
        step: "checking".to_string(),
        message: "Checking Opencode service status on remote host...".to_string(),
        local_url: None,
        remote_url: None,
        local_port: None,
        remote_port: None,
    });

    let status_cmd = build_opencode_exec_cmd("service status", custom_path, workdir);
    let (status_code, status_out, _status_err) = {
        let cl = client.lock().await;
        exec_command(&cl, &status_cmd).await?
    };

    let status_str = status_out.trim().to_lowercase();
    let is_running = (status_code == 0
        && !status_str.contains("stopped")
        && (status_str.contains("http://")
            || status_str.contains("127.0.0.1")
            || !status_str.is_empty()))
        || status_str.contains("http://");

    if is_running {
        let _ = sink.add(OpencodeSessionEvent {
            session_id: session_id.clone(),
            step: "checking".to_string(),
            message: format!("Opencode service is running ({})", status_out.trim()),
            local_url: None,
            remote_url: None,
            local_port: None,
            remote_port: None,
        });
    } else {
        // 3. Start service if not running
        let _ = sink.add(OpencodeSessionEvent {
            session_id: session_id.clone(),
            step: "starting_service".to_string(),
            message: "Opencode service is stopped. Starting background service...".to_string(),
            local_url: None,
            remote_url: None,
            local_port: None,
            remote_port: None,
        });

        let start_cmd = build_opencode_exec_cmd("service start", custom_path, workdir);
        let (start_code, start_out, start_err) = {
            let cl = client.lock().await;
            exec_command(&cl, &start_cmd).await?
        };

        if start_code != 0 && !start_out.contains("http://") {
            let err_msg = if !start_err.is_empty() {
                start_err
            } else {
                start_out
            };
            let _ = sink.add(OpencodeSessionEvent {
                session_id: session_id.clone(),
                step: "error".to_string(),
                message: format!("Failed to start Opencode service: {}", err_msg.trim()),
                local_url: None,
                remote_url: None,
                local_port: None,
                remote_port: None,
            });
            return Err(format!("Failed to start Opencode service: {}", err_msg));
        }

        let _ = sink.add(OpencodeSessionEvent {
            session_id: session_id.clone(),
            step: "starting_service".to_string(),
            message: "Opencode service successfully started.".to_string(),
            local_url: None,
            remote_url: None,
            local_port: None,
            remote_port: None,
        });
    }

    // 4. Pair to obtain URL with token
    let _ = sink.add(OpencodeSessionEvent {
        session_id: session_id.clone(),
        step: "pairing".to_string(),
        message: "Requesting pair token and URL from remote Opencode...".to_string(),
        local_url: None,
        remote_url: None,
        local_port: None,
        remote_port: None,
    });

    let pair_cmd = build_opencode_exec_cmd("pair", custom_path, workdir);
    let (pair_code, pair_out, pair_err) = {
        let cl = client.lock().await;
        exec_command(&cl, &pair_cmd).await?
    };

    if pair_code != 0 && pair_out.trim().is_empty() {
        let err_msg = if !pair_err.is_empty() {
            pair_err
        } else {
            pair_out
        };
        let _ = sink.add(OpencodeSessionEvent {
            session_id: session_id.clone(),
            step: "error".to_string(),
            message: format!("'opencode pair' failed: {}", err_msg.trim()),
            local_url: None,
            remote_url: None,
            local_port: None,
            remote_port: None,
        });
        return Err(format!("'opencode pair' failed: {}", err_msg));
    }

    let (remote_url, remote_port, url_path) = match parse_pair_output(&pair_out) {
        Ok(parsed) => parsed,
        Err(e) => {
            let _ = sink.add(OpencodeSessionEvent {
                session_id: session_id.clone(),
                step: "error".to_string(),
                message: e.clone(),
                local_url: None,
                remote_url: None,
                local_port: None,
                remote_port: None,
            });
            return Err(e);
        }
    };

    // 5. Establish local port forwarding
    let _ = sink.add(OpencodeSessionEvent {
        session_id: session_id.clone(),
        step: "forwarding".to_string(),
        message: format!(
            "Binding local port and forwarding to remote port {}...",
            remote_port
        ),
        local_url: None,
        remote_url: Some(remote_url.clone()),
        local_port: None,
        remote_port: Some(remote_port),
    });

    // Try user preferred port, then remote port, then 0 (auto-assign)
    let preferred_ports = match config.preferred_local_port {
        Some(p) if p > 0 => vec![p, remote_port, 0],
        _ => vec![remote_port, 0],
    };

    let mut bind_res = None;
    for port in preferred_ports {
        let addr = format!("127.0.0.1:{}", port);
        match TcpListener::bind(&addr).await {
            Ok(listener) => {
                bind_res = Some(listener);
                break;
            }
            Err(_) => continue,
        }
    }

    let listener = match bind_res {
        Some(l) => l,
        None => {
            let err_msg = "Failed to bind local port (tried configured and free ports)".to_string();
            let _ = sink.add(OpencodeSessionEvent {
                session_id: session_id.clone(),
                step: "error".to_string(),
                message: err_msg.clone(),
                local_url: None,
                remote_url: Some(remote_url),
                local_port: None,
                remote_port: Some(remote_port),
            });
            return Err(err_msg);
        }
    };

    let local_port = listener
        .local_addr()
        .map_err(|e| e.to_string())?
        .port();

    let local_url = format!("http://127.0.0.1:{}{}", local_port, url_path);

    let (stop_tx, mut stop_rx) = mpsc::channel::<()>(1);
    let is_running_flag = Arc::new(AtomicBool::new(true));

    {
        let mut sessions = active_opencode_sessions().write().await;
        sessions.insert(
            session_id.clone(),
            OpencodeSessionHandle {
                stop_tx,
                is_running: is_running_flag.clone(),
                ssh_client: client.clone(),
                remote_port,
                local_port,
                custom_opencode_path: config.custom_opencode_path.clone(),
                remote_workdir: config.remote_workdir.clone(),
            },
        );
    }

    // 6. Notify Ready!
    let _ = sink.add(OpencodeSessionEvent {
        session_id: session_id.clone(),
        step: "ready".to_string(),
        message: format!(
            "Connected! Local port {} is forwarded to remote {}.",
            local_port, remote_port
        ),
        local_url: Some(local_url),
        remote_url: Some(remote_url),
        local_port: Some(local_port),
        remote_port: Some(remote_port),
    });

    // 7. Background forwarding loop with keepalive health check
    let s_id = session_id.clone();
    let client_for_loop = client.clone();
    tokio::spawn(async move {
        let mut health_interval = tokio::time::interval(std::time::Duration::from_secs(10));
        health_interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);

        loop {
            tokio::select! {
                _ = stop_rx.recv() => {
                    break;
                }
                _ = health_interval.tick() => {
                    // Actively monitor if the underlying SSH connection was dropped
                    let is_closed = {
                        let cl = client_for_loop.lock().await;
                        cl.is_closed()
                    };
                    if is_closed {
                        eprintln!("[OpencodeRemote] SSH connection has closed, terminating forwarding loop.");
                        break;
                    }
                }
                accept_res = listener.accept() => {
                    match accept_res {
                        Ok((mut tcp_stream, _peer_addr)) => {
                            // Ensure low-latency TCP forwarding for web assets & websockets
                            let _ = tcp_stream.set_nodelay(true);

                            let cl = client_for_loop.clone();
                            let rem_p = remote_port as u32;
                            let loc_p = local_port as u32;

                            tokio::spawn(async move {
                                let open_timeout = std::time::Duration::from_secs(10);
                                let open_future = async {
                                    let client_guard = cl.lock().await;
                                    client_guard
                                        .channel_open_direct_tcpip(
                                            "127.0.0.1",
                                            rem_p,
                                            "127.0.0.1",
                                            loc_p,
                                        )
                                        .await
                                };

                                match tokio::time::timeout(open_timeout, open_future).await {
                                    Ok(Ok(ch)) => {
                                        let mut ssh_stream = ch.into_stream();
                                        let _ = tokio::io::copy_bidirectional(
                                            &mut tcp_stream,
                                            &mut ssh_stream,
                                        )
                                        .await;
                                    }
                                    Ok(Err(e)) => {
                                        eprintln!("[OpencodeRemote] Direct-tcpip channel open failed: {}", e);
                                    }
                                    Err(_) => {
                                        eprintln!("[OpencodeRemote] Direct-tcpip channel open timed out after 10s");
                                    }
                                }
                            });
                        }
                        Err(e) => {
                            // Do NOT break on transient socket errors (e.g. aborted handshake, EMFILE)
                            eprintln!("[OpencodeRemote] Transient listener accept error: {}", e);
                            tokio::time::sleep(std::time::Duration::from_millis(100)).await;
                            continue;
                        }
                    }
                }
            }
        }

        let _ = sink.add(OpencodeSessionEvent {
            session_id: s_id.clone(),
            step: "closed".to_string(),
            message: "Opencode session stopped".to_string(),
            local_url: None,
            remote_url: None,
            local_port: None,
            remote_port: None,
        });

        let mut sessions = active_opencode_sessions().write().await;
        sessions.remove(&s_id);
    });

    Ok(())
}

pub async fn stop_opencode_session(session_id: &str) -> Result<(), String> {
    let handle = {
        let mut sessions = active_opencode_sessions().write().await;
        sessions.remove(session_id)
    };
    if let Some(handle) = handle {
        handle.is_running.store(false, Ordering::Relaxed);
        let _ = handle.stop_tx.try_send(());
    }
    Ok(())
}

pub async fn refresh_pair_url(session_id: &str) -> Result<String, String> {
    let (client, local_port, custom_path, workdir) = {
        let sessions = active_opencode_sessions().read().await;
        let handle = sessions
            .get(session_id)
            .ok_or_else(|| format!("Session {} not active", session_id))?;
        (
            handle.ssh_client.clone(),
            handle.local_port,
            handle.custom_opencode_path.clone(),
            handle.remote_workdir.clone(),
        )
    };

    let pair_cmd = build_opencode_exec_cmd(
        "pair",
        custom_path.as_deref(),
        workdir.as_deref(),
    );

    let (code, out, err) = {
        let cl = client.lock().await;
        exec_command(&cl, &pair_cmd).await?
    };

    if code != 0 && out.trim().is_empty() {
        return Err(format!("'opencode pair' failed: {}", err));
    }

    let (_remote_url, _remote_port, url_path) = parse_pair_output(&out)?;
    let local_url = format!("http://127.0.0.1:{}{}", local_port, url_path);
    Ok(local_url)
}

pub async fn control_remote_service(session_id: &str, action: &str) -> Result<String, String> {
    let (client, custom_path, workdir) = {
        let sessions = active_opencode_sessions().read().await;
        let handle = sessions
            .get(session_id)
            .ok_or_else(|| format!("Session {} not active", session_id))?;
        (
            handle.ssh_client.clone(),
            handle.custom_opencode_path.clone(),
            handle.remote_workdir.clone(),
        )
    };

    let subcommand = match action {
        "start" => "service start",
        "stop" => "service stop",
        "restart" => "service restart",
        "status" => "service status",
        other => return Err(format!("Unknown service action: {}", other)),
    };

    let cmd = build_opencode_exec_cmd(
        subcommand,
        custom_path.as_deref(),
        workdir.as_deref(),
    );

    let (code, out, err) = {
        let cl = client.lock().await;
        exec_command(&cl, &cmd).await?
    };

    if code != 0 && out.trim().is_empty() {
        return Err(format!("Service {} failed: {}", action, err));
    }

    Ok(out.trim().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_pair_output() {
        let sample_output = r#"
  Open a link to connect. Links work once and expire in 5 minutes.

  http://127.0.0.1:49374/auth/connect/7JgURgy2-Y-2IXQLm5m8sw

  Over SSH? Forward the port, then open the link on your machine:
  ssh -L 49374:127.0.0.1:49374 <host>
  If port 49374 is busy locally, forward another port and use it in the link.
"#;
        let (full_url, port, path) = parse_pair_output(sample_output).expect("Should parse");
        assert_eq!(port, 49374);
        assert_eq!(path, "/auth/connect/7JgURgy2-Y-2IXQLm5m8sw");
        assert_eq!(full_url, "http://127.0.0.1:49374/auth/connect/7JgURgy2-Y-2IXQLm5m8sw");
    }
}
