/// Session and token management with pluggable storage

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use parking_lot::RwLock;

/// Session data stored during OAuth flow
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub state: String,
    pub code_verifier: String,
    pub created_at: u64,
}

impl Session {
    /// Create a new session
    pub fn new(state: String, code_verifier: String) -> Self {
        let created_at = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        Self {
            state,
            code_verifier,
            created_at,
        }
    }
}

/// Token data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Token {
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub token_type: String,
    pub expires_in: Option<u64>,
    pub expires_at: Option<u64>,
    pub scope: Option<String>,
}

impl Token {
    /// Check if the token is expired
    pub fn is_expired(&self) -> bool {
        if let Some(expires_at) = self.expires_at {
            let now = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs();
            return now >= expires_at;
        }
        false
    }
}

/// Storage interface for sessions and tokens
pub trait SessionStorage: Send + Sync {
    /// Save a session
    fn save_session(&self, state: &str, session: Session) -> Result<(), String>;

    /// Get a session by state
    fn get_session(&self, state: &str) -> Result<Option<Session>, String>;

    /// Delete a session
    fn delete_session(&self, state: &str) -> Result<(), String>;

    /// Save a token
    fn save_token(&self, key: &str, token: Token) -> Result<(), String>;

    /// Get a token by key
    fn get_token(&self, key: &str) -> Result<Option<Token>, String>;

    /// Delete a token
    fn delete_token(&self, key: &str) -> Result<(), String>;
}

/// In-memory storage implementation
///
/// Thread-safe in-memory storage for sessions and tokens.
/// Suitable for testing and simple use cases.
#[derive(Debug, Default)]
pub struct MemoryStorage {
    sessions: Arc<RwLock<HashMap<String, Session>>>,
    tokens: Arc<RwLock<HashMap<String, Token>>>,
}

impl MemoryStorage {
    /// Create a new memory storage instance
    pub fn new() -> Self {
        Self {
            sessions: Arc::new(RwLock::new(HashMap::new())),
            tokens: Arc::new(RwLock::new(HashMap::new())),
        }
    }
}

impl SessionStorage for MemoryStorage {
    fn save_session(&self, state: &str, session: Session) -> Result<(), String> {
        let mut sessions = self.sessions.write();
        sessions.insert(state.to_string(), session);
        Ok(())
    }

    fn get_session(&self, state: &str) -> Result<Option<Session>, String> {
        let sessions = self.sessions.read();
        Ok(sessions.get(state).cloned())
    }

    fn delete_session(&self, state: &str) -> Result<(), String> {
        let mut sessions = self.sessions.write();
        sessions.remove(state);
        Ok(())
    }

    fn save_token(&self, key: &str, token: Token) -> Result<(), String> {
        let mut tokens = self.tokens.write();
        tokens.insert(key.to_string(), token);
        Ok(())
    }

    fn get_token(&self, key: &str) -> Result<Option<Token>, String> {
        let tokens = self.tokens.read();
        Ok(tokens.get(key).cloned())
    }

    fn delete_token(&self, key: &str) -> Result<(), String> {
        let mut tokens = self.tokens.write();
        tokens.remove(key);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_memory_storage_session_operations() {
        let storage = MemoryStorage::new();

        let session = Session::new("test-state".to_string(), "test-verifier".to_string());

        // Save session
        storage
            .save_session("test-state", session.clone())
            .unwrap();

        // Retrieve session
        let retrieved = storage.get_session("test-state").unwrap();
        assert!(retrieved.is_some());
        assert_eq!(retrieved.unwrap().state, "test-state");

        // Delete session
        storage.delete_session("test-state").unwrap();

        // Verify deletion
        let deleted = storage.get_session("test-state").unwrap();
        assert!(deleted.is_none());
    }

    #[test]
    fn test_token_expiration() {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        // Expired token
        let expired_token = Token {
            access_token: "access".to_string(),
            refresh_token: None,
            token_type: "Bearer".to_string(),
            expires_in: Some(3600),
            expires_at: Some(now - 100),
            scope: None,
        };
        assert!(expired_token.is_expired());

        // Valid token
        let valid_token = Token {
            access_token: "access".to_string(),
            refresh_token: None,
            token_type: "Bearer".to_string(),
            expires_in: Some(3600),
            expires_at: Some(now + 3600),
            scope: None,
        };
        assert!(!valid_token.is_expired());
    }
}
