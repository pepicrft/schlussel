use parking_lot::RwLock;
/// Session and token management with pluggable storage
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

/// Session data stored during OAuth flow
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub state: String,
    pub code_verifier: String,
    pub created_at: u64,
    #[serde(default)]
    pub domain: Option<String>,
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
            domain: None,
        }
    }

    /// Create a new session with a domain
    pub fn with_domain(state: String, code_verifier: String, domain: String) -> Self {
        let created_at = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        Self {
            state,
            code_verifier,
            created_at,
            domain: Some(domain),
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

/// File-based storage implementation using XDG conventions
///
/// Stores sessions and tokens in JSON files following XDG Base Directory specification.
/// Tokens are organized by domain for better security and organization.
#[derive(Debug)]
pub struct FileStorage {
    base_path: PathBuf,
}

impl FileStorage {
    /// Create a new file storage instance with a custom application name
    ///
    /// Uses XDG_DATA_HOME (or ~/.local/share on Linux/macOS, AppData on Windows)
    /// to store credentials in <app_name>/
    ///
    /// # Arguments
    ///
    /// * `app_name` - The application name to use for the storage directory
    ///
    /// # Example
    ///
    /// ```
    /// use schlussel::session::FileStorage;
    ///
    /// let storage = FileStorage::new("my-app").unwrap();
    /// // Stores data in ~/.local/share/my-app/ (on Linux/macOS)
    /// ```
    pub fn new(app_name: &str) -> Result<Self, String> {
        let base_path = dirs::data_dir()
            .ok_or_else(|| "Could not determine data directory".to_string())?
            .join(app_name);

        fs::create_dir_all(&base_path)
            .map_err(|e| format!("Failed to create storage directory: {}", e))?;

        Ok(Self { base_path })
    }

    /// Create a file storage instance with a custom path
    ///
    /// # Arguments
    ///
    /// * `path` - The full path to use for storage
    ///
    /// # Example
    ///
    /// ```
    /// use schlussel::session::FileStorage;
    /// use std::path::PathBuf;
    /// use std::env;
    ///
    /// let custom_path = env::temp_dir().join("my-app-storage");
    /// let storage = FileStorage::with_path(custom_path).unwrap();
    /// ```
    pub fn with_path(path: PathBuf) -> Result<Self, String> {
        fs::create_dir_all(&path)
            .map_err(|e| format!("Failed to create storage directory: {}", e))?;

        Ok(Self { base_path: path })
    }

    /// Get the path for a domain's sessions file
    fn sessions_path(&self, domain: &str) -> PathBuf {
        // Sanitize domain for use in filename
        let safe_domain = domain.replace(['/', '\\', ':'], "_");
        self.base_path
            .join(format!("sessions_{}.json", safe_domain))
    }

    /// Get the path for a domain's tokens file
    fn tokens_path(&self, domain: &str) -> PathBuf {
        // Sanitize domain for use in filename
        let safe_domain = domain.replace(['/', '\\', ':'], "_");
        self.base_path.join(format!("tokens_{}.json", safe_domain))
    }

    /// Load sessions for a specific domain
    fn load_sessions(&self, domain: &str) -> Result<HashMap<String, Session>, String> {
        let path = self.sessions_path(domain);
        if !path.exists() {
            return Ok(HashMap::new());
        }

        let content = fs::read_to_string(&path)
            .map_err(|e| format!("Failed to read sessions file: {}", e))?;

        serde_json::from_str(&content).map_err(|e| format!("Failed to parse sessions: {}", e))
    }

    /// Save sessions for a specific domain
    fn save_sessions(
        &self,
        domain: &str,
        sessions: &HashMap<String, Session>,
    ) -> Result<(), String> {
        let content = serde_json::to_string_pretty(sessions)
            .map_err(|e| format!("Failed to serialize sessions: {}", e))?;

        fs::write(self.sessions_path(domain), content)
            .map_err(|e| format!("Failed to write sessions file: {}", e))
    }

    /// Load tokens for a specific domain
    fn load_tokens(&self, domain: &str) -> Result<HashMap<String, Token>, String> {
        let path = self.tokens_path(domain);
        if !path.exists() {
            return Ok(HashMap::new());
        }

        let content =
            fs::read_to_string(&path).map_err(|e| format!("Failed to read tokens file: {}", e))?;

        serde_json::from_str(&content).map_err(|e| format!("Failed to parse tokens: {}", e))
    }

    /// Save tokens for a specific domain
    fn save_tokens(&self, domain: &str, tokens: &HashMap<String, Token>) -> Result<(), String> {
        let content = serde_json::to_string_pretty(tokens)
            .map_err(|e| format!("Failed to serialize tokens: {}", e))?;

        fs::write(self.tokens_path(domain), content)
            .map_err(|e| format!("Failed to write tokens file: {}", e))
    }
}

impl SessionStorage for FileStorage {
    fn save_session(&self, state: &str, session: Session) -> Result<(), String> {
        // Use domain from session, or "default" if not specified
        let domain = session
            .domain
            .clone()
            .unwrap_or_else(|| "default".to_string());
        let mut sessions = self.load_sessions(&domain)?;
        sessions.insert(state.to_string(), session);
        self.save_sessions(&domain, &sessions)
    }

    fn get_session(&self, state: &str) -> Result<Option<Session>, String> {
        // Try to find session in all domain files
        // First try default domain
        let sessions = self.load_sessions("default")?;
        if let Some(session) = sessions.get(state) {
            return Ok(Some(session.clone()));
        }

        // If not found in default, we need to search all session files
        // This is a bit inefficient, but sessions are temporary and not performance-critical
        let entries = fs::read_dir(&self.base_path)
            .map_err(|e| format!("Failed to read storage directory: {}", e))?;

        for entry in entries.flatten() {
            let path = entry.path();
            if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                if name.starts_with("sessions_") && name.ends_with(".json") {
                    // Extract domain from filename
                    let domain = &name[9..name.len() - 5]; // Remove "sessions_" and ".json"
                    if domain != "default" {
                        let sessions = self.load_sessions(domain)?;
                        if let Some(session) = sessions.get(state) {
                            return Ok(Some(session.clone()));
                        }
                    }
                }
            }
        }

        Ok(None)
    }

    fn delete_session(&self, state: &str) -> Result<(), String> {
        // Try to find and delete session from all domain files
        let entries = fs::read_dir(&self.base_path)
            .map_err(|e| format!("Failed to read storage directory: {}", e))?;

        for entry in entries.flatten() {
            let path = entry.path();
            if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                if name.starts_with("sessions_") && name.ends_with(".json") {
                    let domain = &name[9..name.len() - 5];
                    let mut sessions = self.load_sessions(domain)?;
                    if sessions.remove(state).is_some() {
                        self.save_sessions(domain, &sessions)?;
                        return Ok(());
                    }
                }
            }
        }

        Ok(())
    }

    fn save_token(&self, key: &str, token: Token) -> Result<(), String> {
        // Extract domain from the key (format: "domain:token_id" or just use key as-is)
        let domain = if key.contains(':') {
            key.split(':').next().unwrap_or("default")
        } else {
            "default"
        };

        let mut tokens = self.load_tokens(domain)?;
        tokens.insert(key.to_string(), token);
        self.save_tokens(domain, &tokens)
    }

    fn get_token(&self, key: &str) -> Result<Option<Token>, String> {
        let domain = if key.contains(':') {
            key.split(':').next().unwrap_or("default")
        } else {
            "default"
        };

        let tokens = self.load_tokens(domain)?;
        Ok(tokens.get(key).cloned())
    }

    fn delete_token(&self, key: &str) -> Result<(), String> {
        let domain = if key.contains(':') {
            key.split(':').next().unwrap_or("default")
        } else {
            "default"
        };

        let mut tokens = self.load_tokens(domain)?;
        tokens.remove(key);
        self.save_tokens(domain, &tokens)
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
        storage.save_session("test-state", session.clone()).unwrap();

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

    #[test]
    fn test_file_storage_operations() {
        use std::env;

        // Create a temporary directory for testing
        let temp_dir = env::temp_dir().join(format!("schlussel_test_{}", rand::random::<u32>()));
        let storage = FileStorage::with_path(temp_dir.clone()).unwrap();

        // Test session operations
        let session = Session::new("test-state".to_string(), "test-verifier".to_string());
        storage.save_session("test-state", session.clone()).unwrap();

        let retrieved = storage.get_session("test-state").unwrap();
        assert!(retrieved.is_some());
        assert_eq!(retrieved.unwrap().state, "test-state");

        storage.delete_session("test-state").unwrap();
        let deleted = storage.get_session("test-state").unwrap();
        assert!(deleted.is_none());

        // Test token operations with domain binding
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let token = Token {
            access_token: "test-token".to_string(),
            refresh_token: Some("refresh".to_string()),
            token_type: "Bearer".to_string(),
            expires_in: Some(3600),
            expires_at: Some(now + 3600),
            scope: Some("read write".to_string()),
        };

        // Save with domain prefix
        storage
            .save_token("example.com:user1", token.clone())
            .unwrap();

        let retrieved_token = storage.get_token("example.com:user1").unwrap();
        assert!(retrieved_token.is_some());
        assert_eq!(retrieved_token.unwrap().access_token, "test-token");

        storage.delete_token("example.com:user1").unwrap();
        let deleted_token = storage.get_token("example.com:user1").unwrap();
        assert!(deleted_token.is_none());

        // Cleanup
        fs::remove_dir_all(temp_dir).ok();
    }

    #[test]
    fn test_file_storage_session_domain_separation() {
        use std::env;

        let temp_dir = env::temp_dir().join(format!("schlussel_test_{}", rand::random::<u32>()));
        let storage = FileStorage::with_path(temp_dir.clone()).unwrap();

        // Test sessions with different domains
        let session1 = Session::with_domain(
            "state1".to_string(),
            "verifier1".to_string(),
            "github.com".to_string(),
        );
        let session2 = Session::with_domain(
            "state2".to_string(),
            "verifier2".to_string(),
            "gitlab.com".to_string(),
        );

        // Save sessions for different domains
        storage.save_session("state1", session1.clone()).unwrap();
        storage.save_session("state2", session2.clone()).unwrap();

        // Verify they're stored separately
        let retrieved1 = storage.get_session("state1").unwrap();
        let retrieved2 = storage.get_session("state2").unwrap();

        assert!(retrieved1.is_some());
        assert!(retrieved2.is_some());
        assert_eq!(retrieved1.unwrap().domain, Some("github.com".to_string()));
        assert_eq!(retrieved2.unwrap().domain, Some("gitlab.com".to_string()));

        // Verify separate files were created
        assert!(temp_dir.join("sessions_github.com.json").exists());
        assert!(temp_dir.join("sessions_gitlab.com.json").exists());

        // Test deletion
        storage.delete_session("state1").unwrap();
        assert!(storage.get_session("state1").unwrap().is_none());
        assert!(storage.get_session("state2").unwrap().is_some());

        // Cleanup
        fs::remove_dir_all(temp_dir).ok();
    }

    #[test]
    fn test_file_storage_domain_separation() {
        use std::env;

        let temp_dir = env::temp_dir().join(format!("schlussel_test_{}", rand::random::<u32>()));
        let storage = FileStorage::with_path(temp_dir.clone()).unwrap();

        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let token1 = Token {
            access_token: "token1".to_string(),
            refresh_token: None,
            token_type: "Bearer".to_string(),
            expires_in: Some(3600),
            expires_at: Some(now + 3600),
            scope: None,
        };

        let token2 = Token {
            access_token: "token2".to_string(),
            refresh_token: None,
            token_type: "Bearer".to_string(),
            expires_in: Some(3600),
            expires_at: Some(now + 3600),
            scope: None,
        };

        // Save tokens for different domains
        storage
            .save_token("github.com:user1", token1.clone())
            .unwrap();
        storage
            .save_token("gitlab.com:user1", token2.clone())
            .unwrap();

        // Verify they're stored separately
        let retrieved1 = storage.get_token("github.com:user1").unwrap();
        let retrieved2 = storage.get_token("gitlab.com:user1").unwrap();

        assert_eq!(retrieved1.unwrap().access_token, "token1");
        assert_eq!(retrieved2.unwrap().access_token, "token2");

        // Verify separate files were created
        assert!(temp_dir.join("tokens_github.com.json").exists());
        assert!(temp_dir.join("tokens_gitlab.com.json").exists());

        // Cleanup
        fs::remove_dir_all(temp_dir).ok();
    }
}
