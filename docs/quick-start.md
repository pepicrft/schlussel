# 🏃 Quick Start

Get started with Schlussel in 5 minutes!

## Installation

Add to your `Cargo.toml`:

```toml
[dependencies]
schlussel = { git = "https://github.com/tuist/schlussel" }
```

## Device Code Flow (Recommended for CLI)

The easiest way - perfect for command-line applications:

```rust
use schlussel::prelude::*;
use std::sync::Arc;

// 1. Create secure storage
let storage = Arc::new(SecureStorage::new("my-app").unwrap());

// 2. Configure OAuth (using preset!)
let config = OAuthConfig::github("your-client-id", Some("repo user"));

// 3. Create client
let client = OAuthClient::new(config, storage.clone());

// 4. Authorize (opens browser, handles everything)
let token = client.authorize_device().unwrap();

// 5. Save for later use
client.save_token("github.com:my-app", token).unwrap();
```

**What happens:**
1. 📱 Displays a URL and code
2. 🌐 Opens browser automatically
3. ⏳ Waits for you to authorize
4. ✅ Returns your access token

## Authorization Code Flow

For traditional OAuth with callback server:

```rust
use schlussel::prelude::*;
use std::sync::Arc;

let storage = Arc::new(SecureStorage::new("my-app").unwrap());
let config = OAuthConfig::github("client-id", Some("repo user"));
let client = OAuthClient::new(config, storage);

// Starts local server, opens browser, handles callback
let token = client.authorize().unwrap();
```

## Using Tokens

### Automatic Refresh (Recommended)

```rust
let refresher = TokenRefresher::with_file_locking(client, "my-app").unwrap();

// Always returns a valid token (auto-refreshes if needed)
let token = refresher.get_valid_token("github.com:user").unwrap();

// Use the token
println!("Access token: {}", token.access_token);
```

### Proactive Refresh

Refresh before expiration for better reliability:

```rust
// Refresh when 80% of lifetime elapsed
let token = refresher.get_valid_token_with_threshold("github.com:user", 0.8).unwrap();
```

## Next Steps

- 🔌 See [Provider Presets](provider-presets.md) for other OAuth providers
- 💾 Learn about [Storage Backends](storage-backends.md)
- 🔄 Read about [Token Refresh](token-refresh.md) strategies
- 📱 Check out [Swift Integration](swift-integration.md) for iOS apps
