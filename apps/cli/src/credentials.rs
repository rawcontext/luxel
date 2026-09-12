use keyring::Entry;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{CliError, protocol::PairingCredential};

const SERVICE: &str = "media.luxel.command-line.client";
const ACCOUNT: &str = "default";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Credential {
    #[serde(rename = "clientID")]
    pub client_id: Uuid,
    pub secret: String,
}

impl From<PairingCredential> for Credential {
    fn from(value: PairingCredential) -> Self {
        Self {
            client_id: value.client_id,
            secret: value.secret,
        }
    }
}

pub fn load() -> Result<Credential, CliError> {
    let password = Entry::new(SERVICE, ACCOUNT)
        .map_err(|error| CliError::Credential(error.to_string()))?
        .get_password()
        .map_err(|error| match error {
            keyring::Error::NoEntry => CliError::NotPaired,
            error => CliError::Credential(error.to_string()),
        })?;
    serde_json::from_str(&password).map_err(|error| CliError::Credential(error.to_string()))
}

pub fn save(credential: &Credential) -> Result<(), CliError> {
    let password = serde_json::to_string(credential)?;
    Entry::new(SERVICE, ACCOUNT)
        .map_err(|error| CliError::Credential(error.to_string()))?
        .set_password(&password)
        .map_err(|error| CliError::Credential(error.to_string()))
}
