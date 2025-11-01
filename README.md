# Schlussel

A cross-platform OAuth 2.0 library with PKCE support for command-line applications, written in Rust.

## Features

- **OAuth 2.0 Authorization Code Flow** with PKCE (RFC 7636)
- **Cross-platform**: Builds for Linux, macOS, and Windows (x86_64 and ARM64)
- **Pluggable Storage**: Trait-based storage backend (implement `SessionStorage`)
- **Concurrency Control**: Thread-safe token refresh with automatic locking using `parking_lot`
- **C API**: Compatible with any language that supports C FFI
- **Pure Rust**: Safe, fast, and reliable with Rust's memory safety guarantees

## What is PKCE?

PKCE (Proof Key for Code Exchange) is an extension to OAuth 2.0 that makes the authorization code flow more secure for public clients like CLI applications. Instead of using a client secret (which cannot be kept secret in a CLI app), PKCE uses a dynamically generated code challenge.

## Installation

### Rust

Add to your `Cargo.toml`:

```toml
[dependencies]
schlussel = "0.1.0"
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

```rust
use schlussel::prelude::*;
use std::sync::Arc;

// Create storage
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

### C API

```c
#include <schlussel.h>
#include <stdio.h>

int main() {
    // Create storage
    SchlusselStorage* storage = schlussel_storage_memory_create();

    // Configure OAuth
    SchlusselOAuthConfig config = {
        .client_id = "your-client-id",
        .authorization_endpoint = "https://accounts.example.com/oauth/authorize",
        .token_endpoint = "https://accounts.example.com/oauth/token",
        .redirect_uri = "http://localhost:8080/callback",
        .scope = "read write"
    };

    // Create OAuth client
    SchlusselOAuth* client = schlussel_oauth_create(&config, storage);

    // Start OAuth flow
    SchlusselAuthFlow flow;
    SchlusselError err = schlussel_oauth_start_flow(client, &flow);

    if (err == SCHLUSSEL_OK) {
        printf("Please open this URL in your browser:\n%s\n", flow.url);
        printf("State: %s\n", flow.state);

        // ... Wait for callback and exchange code for token ...

        schlussel_auth_flow_free(&flow);
    }

    // Create token refresher
    SchlusselTokenRefresher* refresher = schlussel_token_refresher_create(client);

    // Before process exit, wait for any in-progress refreshes
    schlussel_token_refresher_wait(refresher, "token-key");

    // Cleanup
    schlussel_token_refresher_destroy(refresher);
    schlussel_oauth_destroy(client);
    schlussel_storage_destroy(storage);

    return 0;
}
```

### Zig API

```zig
const std = @import("std");
const schlussel = @import("schlussel");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create storage
    var storage = schlussel.MemoryStorage.init(allocator);
    defer storage.deinit();

    // Configure OAuth
    const config = schlussel.OAuthConfig{
        .client_id = "your-client-id",
        .authorization_endpoint = "https://accounts.example.com/oauth/authorize",
        .token_endpoint = "https://accounts.example.com/oauth/token",
        .redirect_uri = "http://localhost:8080/callback",
        .scope = "read write",
    };

    // Create OAuth client
    var oauth_client = schlussel.OAuth.init(allocator, config, storage.storage());

    // Start OAuth flow
    const flow_result = try oauth_client.startAuthFlow();
    defer allocator.free(flow_result.url);
    defer allocator.free(flow_result.state);

    std.debug.print("Authorization URL: {s}\n", .{flow_result.url});

    // Create token refresher
    var refresher = schlussel.TokenRefresher.init(allocator, &oauth_client);
    defer refresher.deinit();

    // Refresh token with concurrency control
    const token = try refresher.refreshToken("token-key", "refresh-token");
    defer {
        var mut_token = token;
        mut_token.deinit();
    }

    // Before exit, wait for refresh
    refresher.waitForRefresh("token-key");
}
```

### Swift API

```swift
import Schlussel

// Create storage
let storage = try MemoryStorage()

// Configure OAuth
let config = OAuthConfig(
    clientId: "your-client-id",
    authorizationEndpoint: "https://accounts.example.com/oauth/authorize",
    tokenEndpoint: "https://accounts.example.com/oauth/token",
    redirectUri: "myapp://callback",
    scope: "read write"
)

// Create OAuth client
let client = try OAuthClient(config: config, storage: storage)

// Start OAuth flow
let result = try client.startAuthFlow()
print("Authorization URL: \(result.url)")

// Create token refresher
let refresher = try TokenRefresher(client: client)

// Before exit, wait for refresh
defer {
    refresher.waitForRefresh(key: "token-key")
}
```

### Node.js API

```javascript
const { OAuthClient, MemoryStorage, TokenRefresher } = require('@tuist/schlussel');

// Create storage
const storage = new MemoryStorage();

// Configure OAuth
const client = new OAuthClient({
  clientId: 'your-client-id',
  authorizationEndpoint: 'https://accounts.example.com/oauth/authorize',
  tokenEndpoint: 'https://accounts.example.com/oauth/token',
  redirectUri: 'http://localhost:8080/callback',
  scope: 'read write'
}, storage);

// Start OAuth flow
const { url, state } = client.startAuthFlow();
console.log('Open this URL:', url);

// Create token refresher
const refresher = new TokenRefresher(client);

// Before exit, wait for refresh
process.on('beforeExit', () => {
  refresher.waitForRefresh('token-key');
  refresher.destroy();
  client.destroy();
  storage.destroy();
});
```

### Node.js Example (using FFI directly)

```javascript
const ffi = require('ffi-napi');
const ref = require('ref-napi');

const schlussel = ffi.Library('libschlussel', {
  'schlussel_version': ['string', []],
  'schlussel_storage_memory_create': ['pointer', []],
  'schlussel_oauth_create': ['pointer', ['pointer', 'pointer']],
  'schlussel_oauth_start_flow': ['int', ['pointer', 'pointer']],
  // ... other functions
});

const version = schlussel.schlussel_version();
console.log(`Schlussel version: ${version}`);
```

## Architecture

### Components

1. **PKCE Module** (`src/pkce.zig`)
   - Generates cryptographically secure code verifier and challenge
   - Uses SHA256 for challenge generation
   - Base64 URL-safe encoding

2. **Session Management** (`src/session.zig`)
   - Pluggable storage interface via vtable pattern
   - Built-in memory storage for simple use cases
   - Thread-safe operations with mutex locks

3. **OAuth Flow** (`src/oauth.zig`)
   - Authorization URL generation
   - Session lifecycle management
   - Token storage and retrieval

4. **Token Refresher** (`src/oauth.zig`)
   - Prevents concurrent token refreshes
   - Ensures only one refresh per token at a time
   - Supports waiting for in-progress refreshes before process exit

5. **C API** (`src/c_api.zig`)
   - Foreign function interface for C compatibility
   - Opaque pointer types for safety
   - Error code enum for error handling

### Storage Interface

Implement your own storage backend by conforming to the `SessionStorage` interface:

```zig
pub const SessionStorage = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        saveSession: *const fn (ptr: *anyopaque, state: []const u8, session: Session) anyerror!void,
        getSession: *const fn (ptr: *anyopaque, state: []const u8) anyerror!?Session,
        deleteSession: *const fn (ptr: *anyopaque, state: []const u8) anyerror!void,
        saveToken: *const fn (ptr: *anyopaque, key: []const u8, token: Token) anyerror!void,
        getToken: *const fn (ptr: *anyopaque, key: []const u8) anyerror!?Token,
        deleteToken: *const fn (ptr: *anyopaque, key: []const u8) anyerror!void,
    };
};
```

Example storage implementations:
- File-based storage (JSON, SQLite)
- Keychain/Credential Manager integration
- Encrypted storage

## Cross-Platform Builds

The library builds for the following platforms:

- **Linux**: x86_64, aarch64
- **macOS**: x86_64 (Intel), aarch64 (Apple Silicon)
- **Windows**: x86_64, aarch64

Build outputs include:
- Static libraries (`.a` on Unix, `.lib` on Windows)
- Shared libraries (`.so` on Linux, `.dylib` on macOS, `.dll` on Windows)
- C headers (`include/schlussel.h`)

## Development

```bash
# Install dependencies
mise install

# Run tests
mise run test

# Build for all platforms
mise run build

# Run example
zig build example
```

## Project Structure

```
.
├── src/
│   ├── lib.zig           # Main library entry point
│   ├── pkce.zig          # PKCE implementation
│   ├── session.zig       # Session and storage management
│   ├── oauth.zig         # OAuth flow orchestration
│   ├── c_api.zig         # C API bindings
│   └── example.zig       # Example usage
├── include/
│   └── schlussel.h       # C header file
├── test/
│   └── integration_test.zig
├── mise/
│   └── tasks/
│       └── build.sh      # Cross-platform build script
├── build.zig             # Zig build configuration
├── .mise.toml            # Mise configuration
└── README.md
```

## Security Considerations

1. **PKCE is Required**: This library always uses PKCE for enhanced security
2. **State Parameter**: Random state generation to prevent CSRF attacks
3. **Secure Storage**: Use encrypted storage in production (implement custom `SessionStorage`)
4. **Token Lifetime**: Always check token expiration with `token.isExpired()`
5. **HTTPS Only**: Ensure all OAuth endpoints use HTTPS in production

## Contributing

Contributions are welcome! Please ensure:

1. All tests pass: `zig build test`
2. Code is formatted: `zig fmt src/`
3. Cross-platform build works: `mise run build`

## License

See [LICENSE](LICENSE) for details.

## References

- [RFC 7636 - Proof Key for Code Exchange](https://tools.ietf.org/html/rfc7636)
- [RFC 6749 - The OAuth 2.0 Authorization Framework](https://tools.ietf.org/html/rfc6749)
- [OAuth 2.0 for Native Apps (RFC 8252)](https://tools.ietf.org/html/rfc8252)
