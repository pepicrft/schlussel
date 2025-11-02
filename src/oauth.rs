/// OAuth 2.0 flow orchestration
use crate::error::{OAuthError, Result};
use crate::pkce::Pkce;
use crate::session::{Session, SessionStorage, Token};
use parking_lot::Mutex;
use rand::Rng;
use reqwest::blocking::Client;
use serde::Deserialize;
use std::collections::HashMap;
use std::sync::Arc;
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// OAuth 2.0 configuration
#[derive(Debug, Clone)]
pub struct OAuthConfig {
    pub client_id: String,
    pub authorization_endpoint: String,
    pub token_endpoint: String,
    pub redirect_uri: String,
    pub scope: Option<String>,
    /// Optional device authorization endpoint for Device Code Flow (RFC 8628)
    pub device_authorization_endpoint: Option<String>,
}

/// Authorization flow result
#[derive(Debug, Clone)]
pub struct AuthFlowResult {
    pub url: String,
    pub state: String,
}

/// Device authorization response (RFC 8628)
#[derive(Debug, Clone, Deserialize)]
pub struct DeviceAuthorizationResponse {
    pub device_code: String,
    pub user_code: String,
    pub verification_uri: String,
    #[serde(default)]
    pub verification_uri_complete: Option<String>,
    pub expires_in: u64,
    #[serde(default = "default_interval")]
    pub interval: u64,
}

fn default_interval() -> u64 {
    5
}

/// Token response from OAuth server
#[derive(Debug, Clone, Deserialize)]
struct TokenResponse {
    access_token: String,
    #[serde(default)]
    refresh_token: Option<String>,
    token_type: String,
    #[serde(default)]
    expires_in: Option<u64>,
    #[serde(default)]
    scope: Option<String>,
}

/// Error response from OAuth server
#[derive(Debug, Deserialize)]
struct ErrorResponse {
    error: String,
    #[serde(default)]
    error_description: Option<String>,
}

/// OAuth 2.0 client
///
/// Manages OAuth authorization code flow with PKCE and Device Code Flow.
pub struct OAuthClient<S: SessionStorage> {
    config: OAuthConfig,
    storage: Arc<S>,
    http_client: Client,
}

impl<S: SessionStorage> OAuthClient<S> {
    /// Create a new OAuth client
    pub fn new(config: OAuthConfig, storage: Arc<S>) -> Self {
        Self {
            config,
            storage,
            http_client: Client::new(),
        }
    }

    /// Complete authorization code flow with automatic callback server
    ///
    /// This is the recommended method for CLI applications. It:
    /// 1. Starts a local callback server
    /// 2. Opens the authorization URL in the user's browser
    /// 3. Waits for the OAuth callback
    /// 4. Exchanges the code for a token
    ///
    /// Returns the access token or an error.
    pub fn authorize(&self) -> Result<Token> {
        use crate::callback::CallbackServer;

        // Start callback server on random port
        let server = CallbackServer::new()?;
        let redirect_uri = server.redirect_uri();

        // Generate PKCE challenge
        let pkce = Pkce::generate();

        // Generate random state
        let mut rng = rand::thread_rng();
        let state_bytes: [u8; 16] = rng.gen();
        let state = hex::encode(&state_bytes);

        // Save session
        let session = Session::new(state.clone(), pkce.code_verifier().to_string());
        self.storage
            .save_session(&state, session)
            .map_err(OAuthError::StorageError)?;

        // Build authorization URL with callback server's redirect URI
        let mut url = format!(
            "{}?client_id={}&redirect_uri={}&response_type=code&state={}&code_challenge={}&code_challenge_method={}",
            self.config.authorization_endpoint,
            urlencoding::encode(&self.config.client_id),
            urlencoding::encode(&redirect_uri),
            state,
            pkce.code_challenge(),
            Pkce::code_challenge_method()
        );

        if let Some(scope) = &self.config.scope {
            url.push_str(&format!("&scope={}", urlencoding::encode(scope)));
        }

        // Open browser
        println!("\n=== Authorization Required ===");
        println!("Opening browser for authorization...");
        println!("If the browser doesn't open, visit: {}", url);

        let _ = webbrowser::open(&url);

        // Wait for callback (30 second timeout)
        println!("Waiting for authorization...");
        let callback_result = server.wait_for_callback(Duration::from_secs(30))?;

        // Exchange code for token
        self.exchange_code(&callback_result.code, &callback_result.state)
    }

    /// Start the OAuth authorization flow with PKCE
    ///
    /// Generates a PKCE challenge, creates a session, and returns the
    /// authorization URL that the user should open.
    ///
    /// For a complete flow with automatic callback handling, use `authorize()` instead.
    pub fn start_auth_flow(&self) -> Result<AuthFlowResult> {
        // Generate PKCE challenge
        let pkce = Pkce::generate();

        // Generate random state
        let mut rng = rand::thread_rng();
        let state_bytes: [u8; 16] = rng.gen();
        let state = hex::encode(&state_bytes);

        // Save session
        let session = Session::new(state.clone(), pkce.code_verifier().to_string());
        self.storage
            .save_session(&state, session)
            .map_err(OAuthError::StorageError)?;

        // Build authorization URL
        let url = self.build_auth_url(&state, pkce.code_challenge())?;

        Ok(AuthFlowResult { url, state })
    }

    /// Start Device Code Flow (RFC 8628)
    ///
    /// This flow is ideal for input-constrained devices and CLI applications.
    /// Returns device authorization info and automatically polls for completion.
    pub fn authorize_device(&self) -> Result<Token> {
        let device_endpoint = self
            .config
            .device_authorization_endpoint
            .as_ref()
            .ok_or_else(|| {
                OAuthError::InvalidResponse("device_authorization_endpoint not configured".into())
            })?;

        // Step 1: Request device and user codes
        let mut params = vec![("client_id", self.config.client_id.as_str())];
        if let Some(scope) = &self.config.scope {
            params.push(("scope", scope.as_str()));
        }

        let response = self
            .http_client
            .post(device_endpoint)
            .form(&params)
            .send()?;

        if !response.status().is_success() {
            let error: ErrorResponse = response.json()?;
            return Err(OAuthError::OAuthErrorResponse {
                error: error.error,
                description: error.error_description,
            });
        }

        let device_auth: DeviceAuthorizationResponse = response.json()?;

        // Step 2: Display instructions to user
        println!("\n=== Device Authorization ===");
        println!("Please visit: {}", device_auth.verification_uri);
        println!("And enter code: {}", device_auth.user_code);

        if let Some(complete_uri) = &device_auth.verification_uri_complete {
            println!("\nOr visit this URL directly:");
            println!("{}", complete_uri);
        }

        println!("\nWaiting for authorization...");

        // Try to open browser automatically
        if let Some(complete_uri) = &device_auth.verification_uri_complete {
            let _ = webbrowser::open(complete_uri);
        } else {
            let _ = webbrowser::open(&device_auth.verification_uri);
        }

        // Step 3: Poll for token
        self.poll_for_device_token(&device_auth)
    }

    fn poll_for_device_token(&self, device_auth: &DeviceAuthorizationResponse) -> Result<Token> {
        let mut interval = Duration::from_secs(device_auth.interval);
        let expiration = SystemTime::now() + Duration::from_secs(device_auth.expires_in);

        loop {
            if SystemTime::now() > expiration {
                return Err(OAuthError::DeviceCodeExpired);
            }

            thread::sleep(interval);

            let params = vec![
                ("client_id", self.config.client_id.as_str()),
                ("device_code", device_auth.device_code.as_str()),
                ("grant_type", "urn:ietf:params:oauth:grant-type:device_code"),
            ];

            let response = self
                .http_client
                .post(&self.config.token_endpoint)
                .form(&params)
                .send()?;

            if response.status().is_success() {
                let token_response: TokenResponse = response.json()?;
                return Ok(self.convert_token_response(token_response));
            }

            // Handle error responses
            let error: ErrorResponse = response.json()?;
            match error.error.as_str() {
                "authorization_pending" => {
                    // Continue polling
                    continue;
                }
                "slow_down" => {
                    // Increase interval by 5 seconds
                    interval += Duration::from_secs(5);
                    continue;
                }
                "access_denied" => {
                    return Err(OAuthError::AuthorizationDenied);
                }
                "expired_token" => {
                    return Err(OAuthError::DeviceCodeExpired);
                }
                _ => {
                    return Err(OAuthError::OAuthErrorResponse {
                        error: error.error,
                        description: error.error_description,
                    });
                }
            }
        }
    }

    /// Exchange authorization code for access token
    pub fn exchange_code(&self, code: &str, state: &str) -> Result<Token> {
        // Retrieve session
        let session = self
            .storage
            .get_session(state)
            .map_err(OAuthError::StorageError)?
            .ok_or(OAuthError::InvalidState)?;

        // Build token request
        let params = vec![
            ("client_id", self.config.client_id.as_str()),
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", self.config.redirect_uri.as_str()),
            ("code_verifier", session.code_verifier.as_str()),
        ];

        let response = self
            .http_client
            .post(&self.config.token_endpoint)
            .form(&params)
            .send()?;

        if !response.status().is_success() {
            let error: ErrorResponse = response.json()?;
            return Err(OAuthError::OAuthErrorResponse {
                error: error.error,
                description: error.error_description,
            });
        }

        let token_response: TokenResponse = response.json()?;

        // Delete session after successful exchange
        self.storage
            .delete_session(state)
            .map_err(OAuthError::StorageError)?;

        Ok(self.convert_token_response(token_response))
    }

    /// Refresh an access token
    pub fn refresh_token(&self, refresh_token: &str) -> Result<Token> {
        let params = vec![
            ("client_id", self.config.client_id.as_str()),
            ("grant_type", "refresh_token"),
            ("refresh_token", refresh_token),
        ];

        let response = self
            .http_client
            .post(&self.config.token_endpoint)
            .form(&params)
            .send()?;

        if !response.status().is_success() {
            let error: ErrorResponse = response.json()?;
            return Err(OAuthError::OAuthErrorResponse {
                error: error.error,
                description: error.error_description,
            });
        }

        let token_response: TokenResponse = response.json()?;
        Ok(self.convert_token_response(token_response))
    }

    fn convert_token_response(&self, response: TokenResponse) -> Token {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let expires_at = response.expires_in.map(|exp| now + exp);

        Token {
            access_token: response.access_token,
            refresh_token: response.refresh_token,
            token_type: response.token_type,
            expires_in: response.expires_in,
            expires_at,
            scope: response.scope,
        }
    }

    fn build_auth_url(&self, state: &str, code_challenge: &str) -> Result<String> {
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
    pub fn get_token(&self, key: &str) -> Result<Option<Token>> {
        self.storage
            .get_token(key)
            .map_err(OAuthError::StorageError)
    }

    /// Save a token
    pub fn save_token(&self, key: &str, token: Token) -> Result<()> {
        self.storage
            .save_token(key, token)
            .map_err(OAuthError::StorageError)
    }
}

/// Token refresher with concurrency control
///
/// Ensures only one refresh happens at a time for a given token key,
/// both within the same process and across multiple processes.
pub struct TokenRefresher<S: SessionStorage> {
    client: Arc<OAuthClient<S>>,
    refresh_in_progress: Arc<Mutex<HashMap<String, bool>>>,
    lock_manager: Option<Arc<crate::lock::RefreshLockManager>>,
}

impl<S: SessionStorage> TokenRefresher<S> {
    /// Create a new token refresher without cross-process locking
    pub fn new(client: Arc<OAuthClient<S>>) -> Self {
        Self {
            client,
            refresh_in_progress: Arc::new(Mutex::new(HashMap::new())),
            lock_manager: None,
        }
    }

    /// Create a new token refresher with cross-process locking
    ///
    /// This uses file-based locks to coordinate refreshes across multiple processes.
    /// Recommended for production use when multiple processes might refresh the same token.
    ///
    /// # Example
    ///
    /// ```no_run
    /// use schlussel::prelude::*;
    /// use std::sync::Arc;
    ///
    /// let storage = Arc::new(FileStorage::new("my-app").unwrap());
    /// let config = OAuthConfig { /* ... */
    /// # client_id: "test".to_string(),
    /// # authorization_endpoint: "https://test.com/auth".to_string(),
    /// # token_endpoint: "https://test.com/token".to_string(),
    /// # redirect_uri: "http://localhost".to_string(),
    /// # scope: None,
    /// # device_authorization_endpoint: None,
    /// };
    /// let client = Arc::new(OAuthClient::new(config, storage));
    ///
    /// // With cross-process locking
    /// let refresher = TokenRefresher::with_file_locking(client, "my-app").unwrap();
    /// ```
    pub fn with_file_locking(client: Arc<OAuthClient<S>>, app_name: &str) -> Result<Self> {
        let lock_manager = crate::lock::RefreshLockManager::for_app(app_name)?;
        Ok(Self {
            client,
            refresh_in_progress: Arc::new(Mutex::new(HashMap::new())),
            lock_manager: Some(Arc::new(lock_manager)),
        })
    }

    /// Create a new token refresher with a custom lock manager
    pub fn with_lock_manager(
        client: Arc<OAuthClient<S>>,
        lock_manager: Arc<crate::lock::RefreshLockManager>,
    ) -> Self {
        Self {
            client,
            refresh_in_progress: Arc::new(Mutex::new(HashMap::new())),
            lock_manager: Some(lock_manager),
        }
    }

    /// Refresh a token with concurrency control
    ///
    /// If a refresh is already in progress for the key, this will wait
    /// for it to complete and return the refreshed token.
    ///
    /// When configured with file locking, this method is safe to call from
    /// multiple processes simultaneously. It uses a "check-then-refresh" pattern:
    /// 1. Acquire cross-process lock
    /// 2. Re-read the token (another process may have already refreshed it)
    /// 3. Check if token is still expired
    /// 4. Only refresh if still needed
    /// 5. Release lock
    pub fn refresh_token_for_key(&self, key: &str) -> Result<Token> {
        // If we have a lock manager, use cross-process locking
        if let Some(lock_manager) = &self.lock_manager {
            return self.refresh_with_file_lock(key, lock_manager);
        }

        // Otherwise, use in-process locking only
        self.refresh_in_process(key)
    }

    /// Refresh with cross-process file locking (check-then-refresh pattern)
    fn refresh_with_file_lock(
        &self,
        key: &str,
        lock_manager: &crate::lock::RefreshLockManager,
    ) -> Result<Token> {
        // Acquire cross-process lock (blocks until available)
        let _lock = lock_manager.acquire_lock(key)?;

        // Re-read token after acquiring lock (another process may have refreshed it)
        let token = self
            .client
            .get_token(key)?
            .ok_or_else(|| OAuthError::InvalidResponse("Token not found".into()))?;

        // Check if token is still expired
        if !token.is_expired() {
            // Token was already refreshed by another process
            return Ok(token);
        }

        // Token still expired, we need to refresh
        let refresh_token = token.refresh_token.ok_or(OAuthError::NoRefreshToken)?;

        let new_token = self.client.refresh_token(&refresh_token)?;
        self.client.save_token(key, new_token.clone())?;

        Ok(new_token)
        // Lock automatically released on drop
    }

    /// Refresh with in-process locking only
    fn refresh_in_process(&self, key: &str) -> Result<Token> {
        // Get the current token to extract refresh_token
        let current_token = self
            .client
            .get_token(key)?
            .ok_or_else(|| OAuthError::InvalidResponse("Token not found".into()))?;

        let refresh_token = current_token
            .refresh_token
            .ok_or(OAuthError::NoRefreshToken)?;

        // Check if refresh is in progress
        {
            let in_progress = self.refresh_in_progress.lock();
            if in_progress.get(key).copied().unwrap_or(false) {
                drop(in_progress);

                // Wait for refresh to complete
                loop {
                    thread::sleep(Duration::from_millis(100));
                    let in_progress = self.refresh_in_progress.lock();
                    if !in_progress.get(key).copied().unwrap_or(false) {
                        break;
                    }
                }

                // Get the refreshed token
                return self.client.get_token(key)?.ok_or_else(|| {
                    OAuthError::InvalidResponse("Token not found after refresh".into())
                });
            }
        }

        // Mark refresh as in progress
        {
            let mut in_progress = self.refresh_in_progress.lock();
            in_progress.insert(key.to_string(), true);
        }

        // Perform the actual refresh
        let result = self.do_refresh(key, &refresh_token);

        // Mark refresh as complete
        {
            let mut in_progress = self.refresh_in_progress.lock();
            in_progress.remove(key);
        }

        result
    }

    fn do_refresh(&self, key: &str, refresh_token: &str) -> Result<Token> {
        let new_token = self.client.refresh_token(refresh_token)?;
        self.client.save_token(key, new_token.clone())?;
        Ok(new_token)
    }

    /// Wait for any in-progress refresh to complete
    pub fn wait_for_refresh(&self, key: &str) {
        loop {
            let in_progress = self.refresh_in_progress.lock();
            if !in_progress.get(key).copied().unwrap_or(false) {
                break;
            }
            drop(in_progress);
            thread::sleep(Duration::from_millis(100));
        }
    }
}

// Helper modules
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
                _ => {
                    let mut buf = [0; 4];
                    c.encode_utf8(&mut buf)
                        .bytes()
                        .map(|b| format!("%{:02X}", b))
                        .collect()
                }
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
            device_authorization_endpoint: None,
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
            device_authorization_endpoint: None,
        };

        let client = Arc::new(OAuthClient::new(config, storage.clone()));

        // Save a token with refresh token
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let token = Token {
            access_token: "test_access".to_string(),
            refresh_token: Some("test_refresh".to_string()),
            token_type: "Bearer".to_string(),
            expires_in: Some(3600),
            expires_at: Some(now + 3600),
            scope: None,
        };

        client.save_token("test-key", token).unwrap();

        // Verify token was saved
        let saved_token = client.get_token("test-key").unwrap();
        assert!(saved_token.is_some());
    }
}
