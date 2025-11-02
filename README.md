# Schlussel

A cross-platform OAuth 2.0 library with PKCE support for command-line applications, written in Rust.

## Features

- **OAuth 2.0 Authorization Code Flow** with PKCE (RFC 7636)
- **Cross-platform**: Builds for Linux, macOS, and Windows (x86_64 and ARM64)
- **Pluggable Storage**: Trait-based storage backend (implement `SessionStorage`)
- **Concurrency Control**: Thread-safe token refresh with automatic locking using `parking_lot`
- **Pure Rust**: Safe, fast, and reliable with Rust's memory safety guarantees

## What is PKCE?

PKCE (Proof Key for Code Exchange) is an extension to OAuth 2.0 that makes the authorization code flow more secure for public clients like CLI applications. Instead of using a client secret (which cannot be kept secret in a CLI app), PKCE uses a dynamically generated code challenge.

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

#### Using File-Based Storage (Recommended for CLI apps)

```rust
use schlussel::prelude::*;
use std::sync::Arc;

// Create file storage with your app name (uses XDG_DATA_HOME or platform equivalent)
let storage = Arc::new(FileStorage::new("my-app").unwrap());

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

// Save token with domain binding for better organization
// Format: "domain:identifier"
let token = Token { /* ... */ };
client.save_token("accounts.example.com:user@example.com", token).unwrap();

// Create token refresher
let refresher = TokenRefresher::new(client.clone());

// Refresh token with concurrency control
let token = refresher.refresh_token("accounts.example.com:user@example.com", "refresh-token").unwrap();

// Before exit, wait for refresh
refresher.wait_for_refresh("accounts.example.com:user@example.com");
```

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
