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
//! };
//!
//! let client = OAuthClient::new(config, storage);
//! let result = client.start_auth_flow().unwrap();
//! println!("Authorization URL: {}", result.url);
//! ```

pub mod oauth;
pub mod pkce;
pub mod session;

/// Prelude module for convenient imports
pub mod prelude {
    pub use crate::oauth::{AuthFlowResult, OAuthClient, OAuthConfig, TokenRefresher};
    pub use crate::pkce::Pkce;
    pub use crate::session::{FileStorage, MemoryStorage, Session, SessionStorage, Token};
}

#[cfg(test)]
mod tests {
    use super::prelude::*;
    use std::sync::Arc;

    #[test]
    fn test_full_oauth_flow() {
        let storage = Arc::new(MemoryStorage::new());
        let config = OAuthConfig {
            client_id: "test-client".to_string(),
            authorization_endpoint: "https://auth.example.com/authorize".to_string(),
            token_endpoint: "https://auth.example.com/token".to_string(),
            redirect_uri: "http://localhost:8080/callback".to_string(),
            scope: Some("read write".to_string()),
        };

        let client = Arc::new(OAuthClient::new(config, storage.clone()));
        let result = client.start_auth_flow().unwrap();

        assert!(!result.url.is_empty());
        assert!(!result.state.is_empty());

        // Verify session was saved
        let session = storage.get_session(&result.state).unwrap();
        assert!(session.is_some());

        // Test token refresher
        let refresher = TokenRefresher::new(client.clone());
        let token = refresher.refresh_token("test-key", "test-refresh").unwrap();

        assert!(!token.access_token.is_empty());
        assert!(!token.is_expired());
    }
}
