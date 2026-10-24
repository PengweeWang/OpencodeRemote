use crate::frb_generated::StreamSink;
use crate::keys::{self, KeyGenResult};
use crate::opencode::{self, OpencodeConnectConfig, OpencodeSessionEvent};
use crate::ssh::{self, SshConnectConfig};

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

// ---------------- Key Management API ----------------

#[flutter_rust_bridge::frb(sync)]
pub fn generate_key_pair(
    algorithm: String,
    comment: String,
    passphrase: Option<String>,
) -> Result<KeyGenResult, String> {
    keys::generate_key(&algorithm, &comment, passphrase.as_deref())
}

#[flutter_rust_bridge::frb(sync)]
pub fn parse_key_pair(
    private_key_openssh: String,
    passphrase: Option<String>,
) -> Result<KeyGenResult, String> {
    keys::parse_key(&private_key_openssh, passphrase.as_deref())
}

// ---------------- SSH Connectivity Test ----------------

pub async fn test_ssh_connection(config: SshConnectConfig) -> Result<String, String> {
    ssh::test_connection(config).await
}

// ---------------- Opencode Remote Lifecycle & Tunneling ----------------

pub async fn start_opencode_session(
    config: OpencodeConnectConfig,
    sink: StreamSink<OpencodeSessionEvent>,
) -> Result<(), String> {
    opencode::start_opencode_session(config, sink).await
}

pub async fn stop_opencode_session(session_id: String) -> Result<(), String> {
    opencode::stop_opencode_session(&session_id).await
}

pub async fn refresh_opencode_url(session_id: String) -> Result<String, String> {
    opencode::refresh_pair_url(&session_id).await
}

pub async fn control_opencode_service(session_id: String, action: String) -> Result<String, String> {
    opencode::control_remote_service(&session_id, &action).await
}
