/// Error types for Schlussel OAuth operations
use thiserror::Error;

#[derive(Error, Debug)]
pub enum OAuthError {
    #[error("HTTP request failed: {0}")]
    HttpError(#[from] reqwest::Error),

    #[error("JSON parsing failed: {0}")]
    JsonError(#[from] serde_json::Error),

    #[error("Storage error: {0}")]
    StorageError(String),

    #[error("Invalid state parameter")]
    InvalidState,

    #[error("Authorization denied by user")]
    AuthorizationDenied,

    #[error("Device code expired")]
    DeviceCodeExpired,

    #[error("Authorization pending")]
    AuthorizationPending,

    #[error("Slow down polling")]
    SlowDown,

    #[error("Invalid grant: {0}")]
    InvalidGrant(String),

    #[error("Invalid client")]
    InvalidClient,

    #[error("OAuth error: {error}, description: {description:?}")]
    OAuthErrorResponse {
        error: String,
        description: Option<String>,
    },

    #[error("Token expired")]
    TokenExpired,

    #[error("No refresh token available")]
    NoRefreshToken,

    #[error("Invalid response from server: {0}")]
    InvalidResponse(String),

    #[error("Missing required field: {0}")]
    MissingField(String),

    #[error("I/O error: {0}")]
    IoError(#[from] std::io::Error),
}

pub type Result<T> = std::result::Result<T, OAuthError>;
