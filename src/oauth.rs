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

impl OAuthConfig {
    /// Create a GitHub OAuth configuration
    ///
    /// # Arguments
    ///
    /// * `client_id` - Your GitHub OAuth App client ID
    /// * `scopes` - Optional scopes (e.g., "repo user")
    ///
    /// # Example
    ///
    /// ```
    /// use schlussel::oauth::OAuthConfig;
    ///
    /// let config = OAuthConfig::github("my-client-id", Some("repo user"));
    /// ```
    pub fn github(client_id: impl Into<String>, scopes: Option<&str>) -> Self {
        Self {
            client_id: client_id.into(),
            authorization_endpoint: "https://github.com/login/oauth/authorize".to_string(),
            token_endpoint: "https://github.com/login/oauth/access_token".to_string(),
            redirect_uri: "http://127.0.0.1:8080/callback".to_string(),
            scope: scopes.map(|s| s.to_string()),
            device_authorization_endpoint: Some("https://github.com/login/device/code".to_string()),
        }
    }

    /// Create a Google OAuth configuration
    ///
    /// # Arguments
    ///
    /// * `client_id` - Your Google OAuth client ID
    /// * `scopes` - Optional scopes (e.g., "openid email profile")
    ///
    /// # Example
    ///
    /// ```
    /// use schlussel::oauth::OAuthConfig;
    ///
    /// let config = OAuthConfig::google("my-client-id.apps.googleusercontent.com", Some("openid email"));
    /// ```
    pub fn google(client_id: impl Into<String>, scopes: Option<&str>) -> Self {
        Self {
            client_id: client_id.into(),
            authorization_endpoint: "https://accounts.google.com/o/oauth2/v2/auth".to_string(),
            token_endpoint: "https://oauth2.googleapis.com/token".to_string(),
            redirect_uri: "http://127.0.0.1:8080/callback".to_string(),
            scope: scopes.map(|s| s.to_string()),
            device_authorization_endpoint: Some(
                "https://oauth2.googleapis.com/device/code".to_string(),
            ),
        }
    }

    /// Create a Microsoft OAuth configuration
    ///
    /// # Arguments
    ///
    /// * `client_id` - Your Microsoft Application (client) ID
    /// * `tenant` - Tenant ID or "common" for multi-tenant
    /// * `scopes` - Optional scopes (e.g., "User.Read Mail.Read")
    ///
    /// # Example
    ///
    /// ```
    /// use schlussel::oauth::OAuthConfig;
    ///
    /// let config = OAuthConfig::microsoft("my-client-id", "common", Some("User.Read"));
    /// ```
    pub fn microsoft(client_id: impl Into<String>, tenant: &str, scopes: Option<&str>) -> Self {
        Self {
            client_id: client_id.into(),
            authorization_endpoint: format!(
                "https://login.microsoftonline.com/{}/oauth2/v2.0/authorize",
                tenant
            ),
            token_endpoint: format!(
                "https://login.microsoftonline.com/{}/oauth2/v2.0/token",
                tenant
            ),
            redirect_uri: "http://127.0.0.1:8080/callback".to_string(),
            scope: scopes.map(|s| s.to_string()),
            device_authorization_endpoint: Some(format!(
                "https://login.microsoftonline.com/{}/oauth2/v2.0/devicecode",
                tenant
            )),
        }
    }

    /// Create a GitLab OAuth configuration
    ///
    /// # Arguments
    ///
    /// * `client_id` - Your GitLab application ID
    /// * `scopes` - Optional scopes (e.g., "read_user read_api")
    /// * `gitlab_url` - Optional GitLab instance URL (defaults to gitlab.com)
    ///
    /// # Example
    ///
    /// ```
    /// use schlussel::oauth::OAuthConfig;
    ///
    /// // GitLab.com
    /// let config = OAuthConfig::gitlab("my-client-id", Some("read_user"), None);
    ///
    /// // Self-hosted GitLab
    /// let config = OAuthConfig::gitlab("my-client-id", Some("read_user"), Some("https://gitlab.example.com"));
    /// ```
    pub fn gitlab(
        client_id: impl Into<String>,
        scopes: Option<&str>,
        gitlab_url: Option<&str>,
    ) -> Self {
        let base_url = gitlab_url.unwrap_or("https://gitlab.com");
        Self {
            client_id: client_id.into(),
            authorization_endpoint: format!("{}/oauth/authorize", base_url),
            token_endpoint: format!("{}/oauth/token", base_url),
            redirect_uri: "http://127.0.0.1:8080/callback".to_string(),
            scope: scopes.map(|s| s.to_string()),
            device_authorization_endpoint: None, // GitLab doesn't support Device Code Flow yet
        }
    }

    /// Create a Tuist OAuth configuration
    ///
    /// # Arguments
    ///
    /// * `client_id` - Your Tuist application client ID
    /// * `scopes` - Optional scopes
    /// * `tuist_url` - Optional Tuist instance URL (defaults to cloud.tuist.io)
    ///
    /// # Example
    ///
    /// ```
    /// use schlussel::oauth::OAuthConfig;
    ///
    /// // Tuist Cloud
    /// let config = OAuthConfig::tuist("my-client-id", None, None);
    ///
    /// // Self-hosted Tuist
    /// let config = OAuthConfig::tuist("my-client-id", None, Some("https://tuist.example.com"));
    /// ```
    pub fn tuist(
        client_id: impl Into<String>,
        scopes: Option<&str>,
        tuist_url: Option<&str>,
    ) -> Self {
        let base_url = tuist_url.unwrap_or("https://cloud.tuist.io");
        Self {
            client_id: client_id.into(),
            authorization_endpoint: format!("{}/oauth/authorize", base_url),
            token_endpoint: format!("{}/oauth/token", base_url),
            redirect_uri: "http://127.0.0.1:8080/callback".to_string(),
            scope: scopes.map(|s| s.to_string()),
            device_authorization_endpoint: Some(format!("{}/oauth/device/code", base_url)),
        }
    }
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

    /// Get a valid token, automatically refreshing if expired
    ///
    /// This is the recommended method for CLI applications. It:
    /// 1. Retrieves the token from storage
    /// 2. Checks if the token is expired
    /// 3. Automatically refreshes if needed
    /// 4. Returns a valid, non-expired token
    ///
    /// # Example
    ///
    /// ```no_run
    /// use schlussel::prelude::*;
    /// use std::sync::Arc;
    ///
    /// # let storage = Arc::new(MemoryStorage::new());
    /// # let config = OAuthConfig {
    /// #     client_id: "test".to_string(),
    /// #     authorization_endpoint: "https://test.com/auth".to_string(),
    /// #     token_endpoint: "https://test.com/token".to_string(),
    /// #     redirect_uri: "http://localhost".to_string(),
    /// #     scope: None,
    /// #     device_authorization_endpoint: None,
    /// # };
    /// let client = Arc::new(OAuthClient::new(config, storage));
    /// let refresher = TokenRefresher::with_file_locking(client, "my-app").unwrap();
    ///
    /// // Automatically refreshes if expired
    /// let token = refresher.get_valid_token("github.com:user").unwrap();
    /// println!("Access token: {}", token.access_token);
    /// ```
    pub fn get_valid_token(&self, key: &str) -> Result<Token> {
        let token = self
            .client
            .get_token(key)?
            .ok_or_else(|| OAuthError::InvalidResponse("Token not found".into()))?;

        // Check if token is expired
        if token.is_expired() {
            // Token is expired, refresh it
            return self.refresh_token_for_key(key);
        }

        Ok(token)
    }

    /// Get a valid token with proactive refresh
    ///
    /// This method refreshes the token before it actually expires, providing
    /// a safety margin. For example, with a threshold of 0.8, the token will
    /// be refreshed when 80% of its lifetime has elapsed.
    ///
    /// # Arguments
    ///
    /// * `key` - The token key
    /// * `threshold` - Fraction of token lifetime at which to refresh (0.0 to 1.0)
    ///   - 0.8 = refresh when 80% of lifetime elapsed (recommended)
    ///   - 0.9 = refresh when 90% of lifetime elapsed
    ///   - 1.0 = refresh only when expired (same as `get_valid_token`)
    ///
    /// # Example
    ///
    /// ```no_run
    /// use schlussel::prelude::*;
    /// use std::sync::Arc;
    ///
    /// # let storage = Arc::new(MemoryStorage::new());
    /// # let config = OAuthConfig {
    /// #     client_id: "test".to_string(),
    /// #     authorization_endpoint: "https://test.com/auth".to_string(),
    /// #     token_endpoint: "https://test.com/token".to_string(),
    /// #     redirect_uri: "http://localhost".to_string(),
    /// #     scope: None,
    /// #     device_authorization_endpoint: None,
    /// # };
    /// let client = Arc::new(OAuthClient::new(config, storage));
    /// let refresher = TokenRefresher::with_file_locking(client, "my-app").unwrap();
    ///
    /// // Refresh when 80% of token lifetime has elapsed
    /// let token = refresher.get_valid_token_with_threshold("github.com:user", 0.8).unwrap();
    /// ```
    pub fn get_valid_token_with_threshold(&self, key: &str, threshold: f64) -> Result<Token> {
        let threshold = threshold.clamp(0.0, 1.0);

        let token = self
            .client
            .get_token(key)?
            .ok_or_else(|| OAuthError::InvalidResponse("Token not found".into()))?;

        // Check if token should be refreshed
        if self.should_refresh(&token, threshold) {
            return self.refresh_token_for_key(key);
        }

        Ok(token)
    }

    /// Determine if a token should be refreshed based on threshold
    fn should_refresh(&self, token: &Token, threshold: f64) -> bool {
        // If already expired, definitely refresh
        if token.is_expired() {
            return true;
        }

        // If we don't have expiration info, can't proactively refresh
        let (expires_at, expires_in) = match (token.expires_at, token.expires_in) {
            (Some(at), Some(duration)) => (at, duration),
            _ => return false, // No expiration info, assume valid
        };

        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        // Calculate elapsed time as a fraction of total lifetime
        let total_lifetime = expires_in as f64;
        let time_remaining = expires_at.saturating_sub(now) as f64;
        let time_elapsed = total_lifetime - time_remaining;
        let fraction_elapsed = time_elapsed / total_lifetime;

        // Refresh if we've exceeded the threshold
        fraction_elapsed >= threshold
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

    #[test]
    fn test_get_valid_token_not_expired() {
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
        let refresher = TokenRefresher::new(client.clone());

        // Save a valid token
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let token = Token {
            access_token: "valid_token".to_string(),
            refresh_token: Some("refresh".to_string()),
            token_type: "Bearer".to_string(),
            expires_in: Some(3600),
            expires_at: Some(now + 3600), // Valid for another hour
            scope: None,
        };

        client.save_token("test-key", token.clone()).unwrap();

        // get_valid_token should return the existing token without refreshing
        let result = refresher.get_valid_token("test-key").unwrap();
        assert_eq!(result.access_token, "valid_token");
        assert!(!result.is_expired());
    }

    #[test]
    fn test_get_valid_token_with_threshold() {
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
        let refresher = TokenRefresher::new(client.clone());

        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        // Create a token that's only 10% through its lifetime (very fresh)
        let token = Token {
            access_token: "valid_token".to_string(),
            refresh_token: Some("refresh".to_string()),
            token_type: "Bearer".to_string(),
            expires_in: Some(3600),
            expires_at: Some(now + 3240), // 90% of lifetime remaining (10% elapsed)
            scope: None,
        };

        client.save_token("test-key", token.clone()).unwrap();

        // With threshold 0.8, should NOT refresh (only 10% elapsed << 80%)
        let result = refresher.get_valid_token_with_threshold("test-key", 0.8);
        assert!(result.is_ok(), "Failed with error: {:?}", result.err());
        assert_eq!(result.unwrap().access_token, "valid_token");

        // With threshold 0.5, should NOT refresh (10% elapsed < 50%)
        let result = refresher.get_valid_token_with_threshold("test-key", 0.5);
        assert!(result.is_ok());
        assert_eq!(result.unwrap().access_token, "valid_token");

        // Test that threshold is properly clamped - threshold > 1.0 → 1.0
        // Even with threshold 1.0, at 10% elapsed it won't trigger refresh
        let result = refresher.get_valid_token_with_threshold("test-key", 1.5);
        assert!(result.is_ok());
        assert_eq!(result.unwrap().access_token, "valid_token");
    }

    #[test]
    fn test_should_refresh_logic() {
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
        let refresher = TokenRefresher::new(client.clone());

        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        // Test expired token - should always refresh
        let expired_token = Token {
            access_token: "expired".to_string(),
            refresh_token: Some("refresh".to_string()),
            token_type: "Bearer".to_string(),
            expires_in: Some(3600),
            expires_at: Some(now - 100), // Expired
            scope: None,
        };
        assert!(refresher.should_refresh(&expired_token, 0.8));

        // Test token at 50% lifetime - should not refresh with 0.8 threshold
        let halfway_token = Token {
            access_token: "halfway".to_string(),
            refresh_token: Some("refresh".to_string()),
            token_type: "Bearer".to_string(),
            expires_in: Some(3600),
            expires_at: Some(now + 1800), // 50% remaining
            scope: None,
        };
        assert!(!refresher.should_refresh(&halfway_token, 0.8));

        // Test token at 90% lifetime - should refresh with 0.8 threshold
        let nearly_expired_token = Token {
            access_token: "nearly_expired".to_string(),
            refresh_token: Some("refresh".to_string()),
            token_type: "Bearer".to_string(),
            expires_in: Some(3600),
            expires_at: Some(now + 360), // 10% remaining, 90% elapsed
            scope: None,
        };
        assert!(refresher.should_refresh(&nearly_expired_token, 0.8));

        // Test token without expiration info - should not refresh
        let no_expiry_token = Token {
            access_token: "no_expiry".to_string(),
            refresh_token: Some("refresh".to_string()),
            token_type: "Bearer".to_string(),
            expires_in: None,
            expires_at: None,
            scope: None,
        };
        assert!(!refresher.should_refresh(&no_expiry_token, 0.8));
    }

    #[test]
    fn test_github_preset() {
        let config = OAuthConfig::github("test-client-id", Some("repo user"));

        assert_eq!(config.client_id, "test-client-id");
        assert_eq!(
            config.authorization_endpoint,
            "https://github.com/login/oauth/authorize"
        );
        assert_eq!(
            config.token_endpoint,
            "https://github.com/login/oauth/access_token"
        );
        assert_eq!(config.scope, Some("repo user".to_string()));
        assert_eq!(
            config.device_authorization_endpoint,
            Some("https://github.com/login/device/code".to_string())
        );
    }

    #[test]
    fn test_google_preset() {
        let config =
            OAuthConfig::google("client-id.apps.googleusercontent.com", Some("openid email"));

        assert_eq!(config.client_id, "client-id.apps.googleusercontent.com");
        assert_eq!(
            config.authorization_endpoint,
            "https://accounts.google.com/o/oauth2/v2/auth"
        );
        assert_eq!(config.token_endpoint, "https://oauth2.googleapis.com/token");
        assert_eq!(config.scope, Some("openid email".to_string()));
        assert_eq!(
            config.device_authorization_endpoint,
            Some("https://oauth2.googleapis.com/device/code".to_string())
        );
    }

    #[test]
    fn test_microsoft_preset() {
        let config = OAuthConfig::microsoft("test-client-id", "common", Some("User.Read"));

        assert_eq!(config.client_id, "test-client-id");
        assert_eq!(
            config.authorization_endpoint,
            "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
        );
        assert_eq!(
            config.token_endpoint,
            "https://login.microsoftonline.com/common/oauth2/v2.0/token"
        );
        assert_eq!(config.scope, Some("User.Read".to_string()));
        assert_eq!(
            config.device_authorization_endpoint,
            Some("https://login.microsoftonline.com/common/oauth2/v2.0/devicecode".to_string())
        );
    }

    #[test]
    fn test_gitlab_preset() {
        // GitLab.com
        let config = OAuthConfig::gitlab("test-client-id", Some("read_user"), None);

        assert_eq!(config.client_id, "test-client-id");
        assert_eq!(
            config.authorization_endpoint,
            "https://gitlab.com/oauth/authorize"
        );
        assert_eq!(config.token_endpoint, "https://gitlab.com/oauth/token");
        assert_eq!(config.scope, Some("read_user".to_string()));
        assert_eq!(config.device_authorization_endpoint, None);

        // Self-hosted GitLab
        let config = OAuthConfig::gitlab(
            "test-client-id",
            Some("read_user"),
            Some("https://gitlab.example.com"),
        );

        assert_eq!(
            config.authorization_endpoint,
            "https://gitlab.example.com/oauth/authorize"
        );
        assert_eq!(
            config.token_endpoint,
            "https://gitlab.example.com/oauth/token"
        );
    }

    #[test]
    fn test_tuist_preset() {
        // Tuist Cloud
        let config = OAuthConfig::tuist("test-client-id", None, None);

        assert_eq!(config.client_id, "test-client-id");
        assert_eq!(
            config.authorization_endpoint,
            "https://cloud.tuist.io/oauth/authorize"
        );
        assert_eq!(config.token_endpoint, "https://cloud.tuist.io/oauth/token");
        assert_eq!(
            config.device_authorization_endpoint,
            Some("https://cloud.tuist.io/oauth/device/code".to_string())
        );

        // Self-hosted Tuist
        let config = OAuthConfig::tuist("test-client-id", None, Some("https://tuist.example.com"));

        assert_eq!(
            config.authorization_endpoint,
            "https://tuist.example.com/oauth/authorize"
        );
        assert_eq!(
            config.token_endpoint,
            "https://tuist.example.com/oauth/token"
        );
        assert_eq!(
            config.device_authorization_endpoint,
            Some("https://tuist.example.com/oauth/device/code".to_string())
        );
    }
}
