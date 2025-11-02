/// OAuth 2.0 flow orchestration
use crate::pkce::Pkce;
use crate::session::{Session, SessionStorage, Token};
use parking_lot::Mutex;
use rand::Rng;
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

/// OAuth 2.0 configuration
#[derive(Debug, Clone)]
pub struct OAuthConfig {
    pub client_id: String,
    pub authorization_endpoint: String,
    pub token_endpoint: String,
    pub redirect_uri: String,
    pub scope: Option<String>,
}

/// Authorization flow result
#[derive(Debug, Clone)]
pub struct AuthFlowResult {
    pub url: String,
    pub state: String,
}

/// OAuth 2.0 client
///
/// Manages the OAuth authorization code flow with PKCE.
pub struct OAuthClient<S: SessionStorage> {
    config: OAuthConfig,
    storage: Arc<S>,
}

impl<S: SessionStorage> OAuthClient<S> {
    /// Create a new OAuth client
    pub fn new(config: OAuthConfig, storage: Arc<S>) -> Self {
        Self { config, storage }
    }

    /// Start the OAuth authorization flow
    ///
    /// Generates a PKCE challenge, creates a session, and returns the
    /// authorization URL that the user should open.
    pub fn start_auth_flow(&self) -> Result<AuthFlowResult, String> {
        // Generate PKCE challenge
        let pkce = Pkce::generate();

        // Generate random state
        let mut rng = rand::thread_rng();
        let state_bytes: [u8; 16] = rng.gen();
        let state = hex::encode(&state_bytes);

        // Save session
        let session = Session::new(state.clone(), pkce.code_verifier().to_string());
        self.storage.save_session(&state, session)?;

        // Build authorization URL
        let url = self.build_auth_url(&state, pkce.code_challenge())?;

        Ok(AuthFlowResult { url, state })
    }

    fn build_auth_url(&self, state: &str, code_challenge: &str) -> Result<String, String> {
        let mut url = format!(
            "{}?client_id={}&redirect_uri={}&response_type=code&state={}&code_challenge={}&code_challenge_method={}",
            self.config.authorization_endpoint,
            urlencoding::encode(&self.config.client_id),
            urlencoding::encode(&self.config.redirect_uri),
            state,
            code_challenge,
            Pkce::code_challenge_method()
        );

        if let Some(scope) = &self.config.scope {
            url.push_str(&format!("&scope={}", urlencoding::encode(scope)));
        }

        Ok(url)
    }

    /// Get a token by key
    pub fn get_token(&self, key: &str) -> Result<Option<Token>, String> {
        self.storage.get_token(key)
    }

    /// Save a token
    pub fn save_token(&self, key: &str, token: Token) -> Result<(), String> {
        self.storage.save_token(key, token)
    }
}

/// Token refresher with concurrency control
///
/// Ensures only one refresh happens at a time for a given token key.
pub struct TokenRefresher<S: SessionStorage> {
    client: Arc<OAuthClient<S>>,
    refresh_in_progress: Arc<Mutex<HashMap<String, bool>>>,
}

impl<S: SessionStorage> TokenRefresher<S> {
    /// Create a new token refresher
    pub fn new(client: Arc<OAuthClient<S>>) -> Self {
        Self {
            client,
            refresh_in_progress: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Refresh a token with concurrency control
    ///
    /// If a refresh is already in progress for the key, this will wait
    /// for it to complete and return the refreshed token.
    pub fn refresh_token(&self, key: &str, refresh_token: &str) -> Result<Token, String> {
        // Check if refresh is in progress
        {
            let in_progress = self.refresh_in_progress.lock();
            if in_progress.get(key).copied().unwrap_or(false) {
                drop(in_progress);

                // Wait for refresh to complete
                loop {
                    std::thread::sleep(std::time::Duration::from_millis(100));
                    let in_progress = self.refresh_in_progress.lock();
                    if !in_progress.get(key).copied().unwrap_or(false) {
                        break;
                    }
                }

                // Get the refreshed token
                return self
                    .client
                    .get_token(key)?
                    .ok_or_else(|| "Token not found after refresh".to_string());
            }
        }

        // Mark refresh as in progress
        {
            let mut in_progress = self.refresh_in_progress.lock();
            in_progress.insert(key.to_string(), true);
        }

        // Perform the actual refresh
        let result = self.do_refresh(key, refresh_token);

        // Mark refresh as complete
        {
            let mut in_progress = self.refresh_in_progress.lock();
            in_progress.remove(key);
        }

        result
    }

    fn do_refresh(&self, key: &str, refresh_token: &str) -> Result<Token, String> {
        // In a real implementation, this would make an HTTP request to the token endpoint
        // For now, we'll create a mock token
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let token = Token {
            access_token: "new_access_token".to_string(),
            refresh_token: Some(refresh_token.to_string()),
            token_type: "Bearer".to_string(),
            expires_in: Some(3600),
            expires_at: Some(now + 3600),
            scope: None,
        };

        self.client.save_token(key, token.clone())?;

        Ok(token)
    }

    /// Wait for any in-progress refresh to complete
    pub fn wait_for_refresh(&self, key: &str) {
        loop {
            let in_progress = self.refresh_in_progress.lock();
            if !in_progress.get(key).copied().unwrap_or(false) {
                break;
            }
            drop(in_progress);
            std::thread::sleep(std::time::Duration::from_millis(100));
        }
    }
}

// Add hex and urlencoding to dependencies
mod hex {
    pub fn encode(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{:02x}", b)).collect()
    }
}

mod urlencoding {
    pub fn encode(s: &str) -> String {
        s.chars()
            .map(|c| match c {
                'A'..='Z' | 'a'..='z' | '0'..='9' | '-' | '_' | '.' | '~' => c.to_string(),
                ' ' => "+".to_string(),
                _ => format!("%{:02X}", c as u8),
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::session::MemoryStorage;

    #[test]
    fn test_oauth_start_flow() {
        let storage = Arc::new(MemoryStorage::new());
        let config = OAuthConfig {
            client_id: "test-client".to_string(),
            authorization_endpoint: "https://auth.example.com/authorize".to_string(),
            token_endpoint: "https://auth.example.com/token".to_string(),
            redirect_uri: "http://localhost:8080/callback".to_string(),
            scope: Some("read write".to_string()),
        };

        let client = OAuthClient::new(config, storage.clone());
        let result = client.start_auth_flow().unwrap();

        assert!(!result.url.is_empty());
        assert!(!result.state.is_empty());
        assert!(result.url.contains("client_id=test-client"));
        assert!(result.url.contains("code_challenge_method=S256"));
        assert!(result.url.contains("response_type=code"));

        // Verify session was saved
        let session = storage.get_session(&result.state).unwrap();
        assert!(session.is_some());
    }

    #[test]
    fn test_token_refresher() {
        let storage = Arc::new(MemoryStorage::new());
        let config = OAuthConfig {
            client_id: "test-client".to_string(),
            authorization_endpoint: "https://auth.example.com/authorize".to_string(),
            token_endpoint: "https://auth.example.com/token".to_string(),
            redirect_uri: "http://localhost:8080/callback".to_string(),
            scope: None,
        };

        let client = Arc::new(OAuthClient::new(config, storage.clone()));
        let refresher = TokenRefresher::new(client.clone());

        let token = refresher
            .refresh_token("test-key", "test-refresh-token")
            .unwrap();

        assert_eq!(token.access_token, "new_access_token");
        assert_eq!(token.token_type, "Bearer");

        // Verify token was saved
        let saved_token = client.get_token("test-key").unwrap();
        assert!(saved_token.is_some());
    }
}
