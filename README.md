# Schlussel

A cross-platform OAuth 2.0 library with PKCE support for command-line applications, written in Rust.

## Features

- **OAuth 2.0 Authorization Code Flow** with PKCE (RFC 7636)
- **Device Code Flow** (RFC 8628) - Perfect for CLI applications and headless environments
- **Automatic Browser Integration**: Opens authorization URL and handles callback
- **Local Callback Server**: Built-in HTTP server for OAuth redirects
- **HTTP Token Exchange**: Complete implementation with reqwest
- **Cross-platform**: Builds for Linux, macOS, and Windows (x86_64 and ARM64)
- **Pluggable Storage**: Trait-based storage backend (implement `SessionStorage`)
- **Concurrency Control**: Thread-safe token refresh with automatic locking using `parking_lot`
- **Pure Rust**: Safe, fast, and reliable with Rust's memory safety guarantees

## OAuth Flows Explained

### What is PKCE?

PKCE (Proof Key for Code Exchange) is an extension to OAuth 2.0 that makes the authorization code flow more secure for public clients like CLI applications. Instead of using a client secret (which cannot be kept secret in a CLI app), PKCE uses a dynamically generated code challenge.

### Which Flow Should I Use?

#### Device Code Flow (RFC 8628) - **Recommended for CLI**

**When to use:**
- CLI applications
- Headless/remote environments (SSH sessions, Docker containers)
- Input-constrained devices
- When you want the simplest implementation

**Pros:**
- No callback server needed
- Works in any environment where the user has a browser on another device
- Simple to implement
- Better UX for remote/headless scenarios

**Cons:**
- Requires OAuth provider support (GitHub, Google, Microsoft, etc.)
- User needs to manually enter a code (though auto-open helps)

**Example providers:** GitHub, Google, Microsoft, GitLab, Okta

#### Authorization Code Flow with Callback Server

**When to use:**
- Desktop applications with GUI
- Local development environments
- When Device Code Flow is not supported by the OAuth provider

**Pros:**
- Fully automated (no manual code entry)
- Works with any OAuth 2.0 provider
- Faster than Device Code Flow

**Cons:**
- Requires starting a local HTTP server
- May not work in some network environments
- Slightly more complex implementation

### Provider Support

| Provider | Device Code Flow | Authorization Code Flow |
|----------|-----------------|------------------------|
| GitHub | ✅ | ✅ |
| Google | ✅ | ✅ |
| Microsoft | ✅ | ✅ |
| GitLab | ✅ | ✅ |
| Okta | ✅ | ✅ |
| Auth0 | ❌ | ✅ |
| Generic OAuth 2.0 | Varies | ✅ |

## Quick Start

Check out the [examples/](examples/) directory for working examples:

- **[github_device_flow.rs](examples/github_device_flow.rs)** - Device Code Flow with GitHub
- **[github_callback.rs](examples/github_callback.rs)** - Authorization Code Flow with callback server
- **[token_refresh.rs](examples/token_refresh.rs)** - Token expiration and refresh patterns

Run an example:
```bash
export GITHUB_CLIENT_ID="your_client_id"
cargo run --example github_device_flow
```

## Installation

### Rust

Since this library is not yet published to crates.io, add it to your `Cargo.toml` using the Git repository:

```toml
[dependencies]
schlussel = { git = "https://github.com/tuist/schlussel" }
```

Or specify a particular branch, tag, or commit:

```toml
[dependencies]
schlussel = { git = "https://github.com/tuist/schlussel", branch = "main" }
```

### Building from Source

The project uses [Mise](https://mise.jdx.dev/) for tool management:

```bash
# Install Rust via mise
mise install

# Development build
mise run dev
# or: cargo build

# Run tests
mise run test
# or: cargo test

# Cross-platform build for all targets
mise run build
```

## Usage

### Rust API

#### Quick Start: Device Code Flow (Recommended)

The **Device Code Flow** is the easiest way to add OAuth to CLI applications. It works great for headless environments and doesn't require a callback server.

```rust
use schlussel::prelude::*;
use std::sync::Arc;

// Create file storage
let storage = Arc::new(FileStorage::new("my-app").unwrap());

// Configure OAuth with Device Code Flow
let config = OAuthConfig {
    client_id: "your-client-id".to_string(),
    authorization_endpoint: "https://github.com/login/oauth/authorize".to_string(),
    token_endpoint: "https://github.com/login/oauth/access_token".to_string(),
    redirect_uri: "http://127.0.0.1:8080/callback".to_string(),
    scope: Some("repo user".to_string()),
    device_authorization_endpoint: Some("https://github.com/login/device/code".to_string()),
};

// Create OAuth client
let client = OAuthClient::new(config, storage.clone());

// Authorize using Device Code Flow
// This will:
// 1. Display a URL and code to the user
// 2. Open the browser automatically
// 3. Poll for authorization completion
// 4. Return the access token
match client.authorize_device() {
    Ok(token) => {
        println!("Successfully authorized!");
        println!("Access token: {}", token.access_token);
        
        // Save token for later use
        client.save_token("github.com:my-app", token).unwrap();
    }
    Err(e) => eprintln!("Authorization failed: {}", e),
}
```

#### Authorization Code Flow with Automatic Callback

For traditional OAuth with automatic browser handling and local callback server:

```rust
use schlussel::prelude::*;
use std::sync::Arc;

// Create file storage
let storage = Arc::new(FileStorage::new("my-app").unwrap());

// Configure OAuth (note: device_authorization_endpoint is optional for this flow)
let config = OAuthConfig {
    client_id: "your-client-id".to_string(),
    authorization_endpoint: "https://accounts.example.com/oauth/authorize".to_string(),
    token_endpoint: "https://accounts.example.com/token".to_string(),
    redirect_uri: "http://127.0.0.1/callback".to_string(), // Will be overridden by callback server
    scope: Some("read write".to_string()),
    device_authorization_endpoint: None,
};

// Create OAuth client
let client = OAuthClient::new(config, storage.clone());

// Complete authorization flow automatically
// This will:
// 1. Start a local callback server
// 2. Open the browser with the authorization URL
// 3. Wait for the OAuth callback
// 4. Exchange the code for a token
match client.authorize() {
    Ok(token) => {
        println!("Successfully authorized!");
        
        // Save token with domain:identifier format
        client.save_token("example.com:user@example.com", token).unwrap();
    }
    Err(e) => eprintln!("Authorization failed: {}", e),
}
```

#### Manual Flow Control

For more control over the OAuth flow:

```rust
use schlussel::prelude::*;
use std::sync::Arc;

let storage = Arc::new(FileStorage::new("my-app").unwrap());
let config = OAuthConfig {
    client_id: "your-client-id".to_string(),
    authorization_endpoint: "https://accounts.example.com/oauth/authorize".to_string(),
    token_endpoint: "https://accounts.example.com/token".to_string(),
    redirect_uri: "http://localhost:8080/callback".to_string(),
    scope: Some("read write".to_string()),
    device_authorization_endpoint: None,
};

let client = OAuthClient::new(config, storage.clone());

// Start auth flow and get URL
let result = client.start_auth_flow().unwrap();
println!("Please visit: {}", result.url);

// ... user completes authorization in browser ...

// Exchange code for token (you need to capture code and state from callback)
let token = client.exchange_code("authorization-code", &result.state).unwrap();

// Save token
client.save_token("example.com:user", token).unwrap();
```

#### Token Refresh

```rust
use schlussel::prelude::*;
use std::sync::Arc;

let client = Arc::new(OAuthClient::new(config, storage.clone()));

// Get existing token
let mut token = client.get_token("example.com:user").unwrap().unwrap();

// Check if expired and refresh
if token.is_expired() {
    if let Some(refresh_token) = &token.refresh_token {
        token = client.refresh_token(refresh_token).unwrap();
        client.save_token("example.com:user", token.clone()).unwrap();
    }
}

// Use token
println!("Access token: {}", token.access_token);
```

#### Thread-Safe Token Refresh (In-Process)

For concurrent applications within a single process:

```rust
use schlussel::prelude::*;
use std::sync::Arc;

let client = Arc::new(OAuthClient::new(config, storage));
let refresher = TokenRefresher::new(client.clone());

// Refresh token with in-process concurrency control
// If another thread is already refreshing this token, this will wait
let token = refresher.refresh_token_for_key("example.com:user").unwrap();

// Before application exit, wait for any pending refreshes
refresher.wait_for_refresh("example.com:user");
```

#### Cross-Process Token Refresh (Recommended for Production)

For applications where multiple processes might refresh the same token (e.g., cron jobs, parallel CI/CD pipelines, multiple CLI instances):

```rust
use schlussel::prelude::*;
use std::sync::Arc;

let client = Arc::new(OAuthClient::new(config, storage));

// Create refresher with cross-process file locking
let refresher = TokenRefresher::with_file_locking(client.clone(), "my-app").unwrap();

// Safe to call from multiple processes simultaneously
// Uses "check-then-refresh" pattern:
// 1. Acquires cross-process lock
// 2. Re-reads token (another process may have refreshed it)
// 3. Checks if still expired
// 4. Only refreshes if needed
// 5. Releases lock
let token = refresher.refresh_token_for_key("example.com:user").unwrap();
```

**Benefits of cross-process locking:**
- ✅ Prevents duplicate refresh HTTP requests
- ✅ Avoids race conditions across processes
- ✅ Efficient: only one process actually refreshes
- ✅ Safe for parallel execution (cron jobs, CI/CD, etc.)
- ✅ Automatic with file-based locks (works on Unix, Linux, macOS, Windows)

#### Using In-Memory Storage (For testing)

```rust
use schlussel::prelude::*;
use std::sync::Arc;

// Create in-memory storage
let storage = Arc::new(MemoryStorage::new());

// Configure OAuth
let config = OAuthConfig {
    client_id: "your-client-id".to_string(),
    authorization_endpoint: "https://accounts.example.com/oauth/authorize".to_string(),
    token_endpoint: "https://accounts.example.com/token".to_string(),
    redirect_uri: "http://localhost:8080/callback".to_string(),
    scope: Some("read write".to_string()),
};

// Create OAuth client
let client = Arc::new(OAuthClient::new(config, storage.clone()));

// Start OAuth flow
let result = client.start_auth_flow().unwrap();
println!("Authorization URL: {}", result.url);

// Create token refresher
let refresher = TokenRefresher::new(client.clone());

// Refresh token with concurrency control
let token = refresher.refresh_token("token-key", "refresh-token").unwrap();

// Before exit, wait for refresh
refresher.wait_for_refresh("token-key");
```


## Architecture

### Components

1. **PKCE Module** (`src/pkce.rs`)
   - Generates cryptographically secure code verifier and challenge
   - Uses SHA256 for challenge generation
   - Base64 URL-safe encoding

2. **Session Management** (`src/session.rs`)
   - Trait-based storage interface
   - Built-in memory storage for simple use cases
   - Thread-safe operations with `parking_lot` mutex

3. **OAuth Flow** (`src/oauth.rs`)
   - Authorization URL generation
   - Session lifecycle management
   - Token storage and retrieval
   - Token refresher with concurrency control

### Storage Backends

#### Built-in Storage Options

1. **FileStorage** (Recommended for production CLI apps)
   - Stores sessions and tokens in JSON files
   - Follows XDG Base Directory specification
   - Configurable application name for storage path
   - Location (when using `FileStorage::new("my-app")`):
     - Linux/macOS: `~/.local/share/my-app/`
     - Windows: `%APPDATA%\my-app\`
   - **Domain-based organization**: Both sessions and tokens are stored in separate files per domain
     - Session format: `sessions_<domain>.json`
     - Token format: `tokens_<domain>.json`
     - Example: `sessions_github.com.json`, `tokens_github.com.json`
   - Sessions can optionally specify a domain using `Session::with_domain()`
     - If no domain is specified, defaults to `sessions_default.json`
   - Token keys use format: `domain:identifier`
     - Example: `github.com:user@example.com`
   - Alternative: Use `FileStorage::with_path(path)` for custom directory

2. **MemoryStorage**
   - In-memory storage using `HashMap`
   - Thread-safe with `parking_lot::RwLock`
   - Not persistent (data lost on exit)
   - Suitable for testing

#### Custom Storage

Implement your own storage backend by implementing the `SessionStorage` trait:

```rust
pub trait SessionStorage: Send + Sync {
    fn save_session(&self, state: &str, session: Session) -> Result<(), String>;
    fn get_session(&self, state: &str) -> Result<Option<Session>, String>;
    fn delete_session(&self, state: &str) -> Result<(), String>;
    fn save_token(&self, key: &str, token: Token) -> Result<(), String>;
    fn get_token(&self, key: &str) -> Result<Option<Token>, String>;
    fn delete_token(&self, key: &str) -> Result<(), String>;
}
```

Potential custom implementations:
- SQLite database
- Encrypted file storage
- Keychain/Credential Manager integration (OS-specific)
- Cloud-synced storage

## Cross-Platform Builds

The library builds for the following platforms:

- **Linux**: x86_64, aarch64
- **macOS**: x86_64 (Intel), aarch64 (Apple Silicon)
- **Windows**: x86_64, aarch64

## Development

```bash
# Install dependencies
mise install

# Run tests
mise run test

# Build library
mise run dev

# Build for all platforms
mise run build
```

## Project Structure

```
.
├── src/
│   ├── lib.rs            # Main library entry point
│   ├── pkce.rs           # PKCE implementation
│   ├── session.rs        # Session and storage management
│   └── oauth.rs          # OAuth flow and token refresher
├── mise/
│   └── tasks/            # Mise task scripts
│       ├── build         # Cross-platform build script
│       ├── dev           # Development build
│       └── test          # Test runner
├── Cargo.toml            # Rust package configuration
├── cbindgen.toml         # C binding generation config
├── .mise.toml            # Mise configuration
└── README.md
```

## Security Considerations

1. **PKCE is Required**: This library always uses PKCE for enhanced security
2. **State Parameter**: Random state generation to prevent CSRF attacks
3. **Secure Storage**: Use encrypted storage in production (implement custom `SessionStorage`)
4. **Token Lifetime**: Always check token expiration with `token.is_expired()`
5. **HTTPS Only**: Ensure all OAuth endpoints use HTTPS in production

## Contributing

Contributions are welcome! Please ensure:

1. All tests pass: `cargo test`
2. Code is formatted: `cargo fmt`
3. Code passes linting: `cargo clippy`

## License

See [LICENSE](LICENSE) for details.

## References

- [RFC 7636 - Proof Key for Code Exchange](https://tools.ietf.org/html/rfc7636)
- [RFC 6749 - The OAuth 2.0 Authorization Framework](https://tools.ietf.org/html/rfc6749)
- [OAuth 2.0 for Native Apps (RFC 8252)](https://tools.ietf.org/html/rfc8252)
