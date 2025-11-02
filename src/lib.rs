//! Schlussel - Cross-platform OAuth 2.0 with PKCE for CLI applications
//!
//! This library provides OAuth 2.0 authorization code flow with PKCE
//! (Proof Key for Code Exchange) for command-line applications.
//!
//! # Features
//!
//! - OAuth 2.0 authorization code flow with PKCE (RFC 7636)
//! - Pluggable storage backend
//! - Thread-safe token refresh with concurrency control
//! - C FFI for cross-language compatibility
//!
//! # Example
//!
//! ```
//! use schlussel::prelude::*;
//! use std::sync::Arc;
//!
//! let storage = Arc::new(MemoryStorage::new());
//! let config = OAuthConfig {
//!     client_id: "your-client-id".to_string(),
//!     authorization_endpoint: "https://auth.example.com/authorize".to_string(),
//!     token_endpoint: "https://auth.example.com/token".to_string(),
//!     redirect_uri: "http://localhost:8080/callback".to_string(),
//!     scope: Some("read write".to_string()),
//!     device_authorization_endpoint: None,
//! };
//!
//! let client = OAuthClient::new(config, storage);
//! let result = client.start_auth_flow().unwrap();
//! println!("Authorization URL: {}", result.url);
//! ```

pub mod callback;
pub mod error;
pub mod lock;
pub mod oauth;
pub mod pkce;
pub mod session;

/// Prelude module for convenient imports
pub mod prelude {
    pub use crate::callback::{CallbackResult, CallbackServer};
    pub use crate::error::{OAuthError, Result};
    pub use crate::lock::{RefreshLock, RefreshLockManager};
    pub use crate::oauth::{
        AuthFlowResult, DeviceAuthorizationResponse, OAuthClient, OAuthConfig, TokenRefresher,
    };
    pub use crate::pkce::Pkce;
    pub use crate::session::{FileStorage, MemoryStorage, Session, SessionStorage, Token};
}

#[cfg(test)]
mod tests {
    use super::prelude::*;
    use std::sync::Arc;

    #[test]
    fn test_full_oauth_flow() {
        use std::time::{SystemTime, UNIX_EPOCH};

        let storage = Arc::new(MemoryStorage::new());
        let config = OAuthConfig {
            client_id: "test-client".to_string(),
            authorization_endpoint: "https://auth.example.com/authorize".to_string(),
            token_endpoint: "https://auth.example.com/token".to_string(),
            redirect_uri: "http://localhost:8080/callback".to_string(),
            scope: Some("read write".to_string()),
            device_authorization_endpoint: None,
        };

        let client = Arc::new(OAuthClient::new(config, storage.clone()));
        let result = client.start_auth_flow().unwrap();

        assert!(!result.url.is_empty());
        assert!(!result.state.is_empty());

        // Verify session was saved
        let session = storage.get_session(&result.state).unwrap();
        assert!(session.is_some());

        // Test token storage and retrieval
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let token = Token {
            access_token: "test_access_token".to_string(),
            refresh_token: Some("test_refresh_token".to_string()),
            token_type: "Bearer".to_string(),
            expires_in: Some(3600),
            expires_at: Some(now + 3600),
            scope: Some("read write".to_string()),
        };

        client.save_token("test-key", token.clone()).unwrap();

        let retrieved = client.get_token("test-key").unwrap();
        assert!(retrieved.is_some());
        assert_eq!(retrieved.unwrap().access_token, "test_access_token");
    }
}
