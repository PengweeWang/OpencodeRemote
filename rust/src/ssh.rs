use std::sync::Arc;
use russh::client::{self, Config, Handler};
use russh::keys::PublicKeyOrCertificate;
use russh::keys::PrivateKey;
use russh::ChannelMsg;

#[derive(Clone, Debug)]
pub struct SshConnectConfig {
    pub host: String,
    pub port: u16,
    pub username: String,
    pub auth_type: String, // "password" or "key"
    pub password: Option<String>,
    pub private_key: Option<String>,
    pub passphrase: Option<String>,
}

#[derive(Clone)]
pub struct SshClientHandler {}

impl Handler for SshClientHandler {
    type Error = russh::Error;

    async fn check_server_key(
        &mut self,
        _server_public_key: &PublicKeyOrCertificate,
    ) -> Result<bool, Self::Error> {
        // In mobile client context, accept remote server host keys
        Ok(true)
    }
}

pub async fn create_ssh_client(
    config: &SshConnectConfig,
) -> Result<client::Handle<SshClientHandler>, String> {
    let ssh_config = Arc::new(Config {
        inactivity_timeout: Some(std::time::Duration::from_secs(60)),
        ..Config::default()
    });

    let addr = (config.host.as_str(), config.port);
    let mut handle = client::connect(ssh_config, addr, SshClientHandler {})
        .await
        .map_err(|e| format!("Failed to connect to {}:{}: {}", config.host, config.port, e))?;

    let auth_ok = match config.auth_type.to_lowercase().as_str() {
        "password" => {
            let pwd = config.password.clone().unwrap_or_default();
            handle
                .authenticate_password(&config.username, pwd)
                .await
                .map_err(|e| format!("Password authentication failed: {}", e))?
        }
        "key" => {
            let key_str = config
                .private_key
                .clone()
                .ok_or_else(|| "Private key is required for key authentication".to_string())?;
            let raw_key = PrivateKey::from_openssh(&key_str)
                .map_err(|e| format!("Failed to parse private key: {}", e))?;

            let key = if raw_key.is_encrypted() {
                let pass = config
                    .passphrase
                    .clone()
                    .ok_or_else(|| "Private key is encrypted; passphrase required".to_string())?;
                raw_key
                    .decrypt(&pass)
                    .map_err(|e| format!("Key decryption failed: {}", e))?
            } else {
                raw_key
            };

            handle
                .authenticate_publickey(
                    &config.username,
                    russh::keys::PrivateKeyWithHashAlg::new(Arc::new(key), None),
                )
                .await
                .map_err(|e| format!("Public key authentication failed: {}", e))?
        }
        other => return Err(format!("Unsupported auth type: {}", other)),
    };

    if !matches!(auth_ok, russh::client::AuthResult::Success) {
        return Err("SSH authentication denied by server".to_string());
    }

    Ok(handle)
}

pub async fn exec_command(
    client: &client::Handle<SshClientHandler>,
    command: &str,
) -> Result<(i32, String, String), String> {
    let mut channel = client
        .channel_open_session()
        .await
        .map_err(|e| format!("Failed to open session channel: {}", e))?;

    channel
        .exec(true, command)
        .await
        .map_err(|e| format!("Failed to execute command '{}': {}", command, e))?;

    let mut stdout = Vec::new();
    let mut stderr = Vec::new();
    let mut exit_status = 0i32;

    while let Some(msg) = channel.wait().await {
        match msg {
            ChannelMsg::Data { ref data } => {
                stdout.extend_from_slice(data);
            }
            ChannelMsg::ExtendedData { ref data, .. } => {
                stderr.extend_from_slice(data);
            }
            ChannelMsg::ExitStatus { exit_status: code } => {
                exit_status = code as i32;
            }
            ChannelMsg::Eof | ChannelMsg::Close => {
                break;
            }
            _ => {}
        }
    }

    let out_str = String::from_utf8_lossy(&stdout).to_string();
    let err_str = String::from_utf8_lossy(&stderr).to_string();

    Ok((exit_status, out_str, err_str))
}

pub async fn test_connection(config: SshConnectConfig) -> Result<String, String> {
    let client = create_ssh_client(&config).await?;
    let (exit_code, out, err) = exec_command(&client, "echo __SSH_CONNECTION_OK__").await?;
    if exit_code == 0 && out.contains("__SSH_CONNECTION_OK__") {
        Ok(format!(
            "Successfully connected to {}@{}:{}",
            config.username, config.host, config.port
        ))
    } else {
        Err(format!(
            "Connection established but test command failed (exit {}): {}",
            exit_code,
            if !err.is_empty() { err } else { out }
        ))
    }
}
