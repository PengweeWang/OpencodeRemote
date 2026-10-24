use ssh_key::private::RsaKeypair;
use ssh_key::rand_core::OsRng;
use ssh_key::{Algorithm, EcdsaCurve, HashAlg, LineEnding, PrivateKey};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KeyGenResult {
    pub algorithm: String,
    pub comment: String,
    pub public_key_openssh: String,
    pub private_key_openssh: String,
    pub fingerprint_sha256: String,
    pub is_encrypted: bool,
}

pub fn generate_key(
    algorithm: &str,
    comment: &str,
    passphrase: Option<&str>,
) -> Result<KeyGenResult, String> {
    let mut rng = OsRng;
    let mut privkey = match algorithm.to_lowercase().as_str() {
        "ed25519" => PrivateKey::random(&mut rng, Algorithm::Ed25519)
            .map_err(|e| format!("Failed to generate Ed25519 key: {}", e))?,
        "rsa4096" => {
            let rsa_kp = RsaKeypair::random(&mut rng, 4096)
                .map_err(|e| format!("Failed to generate RSA 4096: {}", e))?;
            PrivateKey::from(rsa_kp)
        }
        "rsa2048" | "rsa" => {
            let rsa_kp = RsaKeypair::random(&mut rng, 2048)
                .map_err(|e| format!("Failed to generate RSA 2048: {}", e))?;
            PrivateKey::from(rsa_kp)
        }
        "ecdsa" | "ecdsa_p256" | "p256" => PrivateKey::random(
            &mut rng,
            Algorithm::Ecdsa {
                curve: EcdsaCurve::NistP256,
            },
        )
        .map_err(|e| format!("Failed to generate ECDSA key: {}", e))?,
        other => return Err(format!("Unsupported algorithm: {}", other)),
    };

    if !comment.is_empty() {
        privkey.set_comment(comment);
    }

    let (privkey, is_encrypted) = if let Some(pass) = passphrase {
        if !pass.is_empty() {
            let enc_key = privkey
                .encrypt(&mut rng, pass)
                .map_err(|e| format!("Failed to encrypt key with passphrase: {}", e))?;
            (enc_key, true)
        } else {
            (privkey, false)
        }
    } else {
        (privkey, false)
    };

    let private_key_openssh = privkey
        .to_openssh(LineEnding::LF)
        .map_err(|e| format!("Failed to encode private key: {}", e))?
        .to_string();

    let pubkey = privkey.public_key();
    let public_key_openssh = pubkey
        .to_openssh()
        .map_err(|e| format!("Failed to encode public key: {}", e))?;
    let fingerprint_sha256 = pubkey.fingerprint(HashAlg::Sha256).to_string();

    Ok(KeyGenResult {
        algorithm: algorithm.to_uppercase(),
        comment: comment.to_string(),
        public_key_openssh,
        private_key_openssh,
        fingerprint_sha256,
        is_encrypted,
    })
}

pub fn parse_key(
    private_key_openssh: &str,
    passphrase: Option<&str>,
) -> Result<KeyGenResult, String> {
    let raw_key = PrivateKey::from_openssh(private_key_openssh)
        .map_err(|e| format!("Invalid OpenSSH private key format: {}", e))?;

    let is_encrypted = raw_key.is_encrypted();
    let privkey = if is_encrypted {
        if let Some(pass) = passphrase {
            raw_key
                .decrypt(pass)
                .map_err(|e| format!("Decryption failed (incorrect passphrase): {}", e))?
        } else {
            return Err("Key is passphrase-protected, please provide passphrase".to_string());
        }
    } else {
        raw_key
    };

    let comment = privkey.comment().to_string();
    let pubkey = privkey.public_key();
    let algo_str = match pubkey.algorithm() {
        Algorithm::Ed25519 => "ED25519".to_string(),
        Algorithm::Rsa { .. } => "RSA".to_string(),
        Algorithm::Ecdsa { curve } => format!("ECDSA-{:?}", curve).to_uppercase(),
        other => format!("{:?}", other),
    };

    let public_key_openssh = pubkey
        .to_openssh()
        .map_err(|e| format!("Failed to encode public key: {}", e))?;
    let fingerprint_sha256 = pubkey.fingerprint(HashAlg::Sha256).to_string();

    Ok(KeyGenResult {
        algorithm: algo_str,
        comment,
        public_key_openssh,
        private_key_openssh: private_key_openssh.to_string(),
        fingerprint_sha256,
        is_encrypted,
    })
}
