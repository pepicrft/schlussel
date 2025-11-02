# 🔐 Schlussel

> **Secure OAuth 2.0 for CLI applications** - Written in Rust, works everywhere 🦀

OAuth authentication made simple for command-line tools. No more copying tokens or managing credentials manually!

---

## ✨ Features

🔑 **Multiple OAuth Flows**
- Device Code Flow (perfect for CLI!)
- Authorization Code Flow with PKCE
- Automatic browser handling

🔒 **Secure by Default**
- OS credential manager integration (Keychain/Credential Manager)
- Cross-process token refresh locking
- Automatic token refresh

⚡ **Developer Friendly**
- Provider presets (GitHub, Google, Microsoft, GitLab, Tuist)
- One-line configuration
- Automatic expiration handling

🌍 **Cross-Platform**
- Linux, macOS, Windows
- x86_64 and ARM64

---

## 🚀 Quick Start

### Installation

```toml
[dependencies]
schlussel = { git = "https://github.com/tuist/schlussel" }
```

### Authenticate with GitHub (3 lines!)

```rust
use schlussel::prelude::*;
use std::sync::Arc;

let storage = Arc::new(SecureStorage::new("my-app").unwrap());
let config = OAuthConfig::github("your-client-id", Some("repo user"));
let client = OAuthClient::new(config, storage);

// That's it! Opens browser, handles OAuth, returns token
let token = client.authorize_device().unwrap();
```

---

## 📖 Documentation

👉 **[Full Documentation](docs/README.md)**

Quick links:
- 🏃 [Quick Start Guide](docs/quick-start.md)
- 🔌 [Provider Presets](docs/provider-presets.md) - GitHub, Google, Microsoft, etc.
- 💾 [Storage Options](docs/storage-backends.md) - Secure, File, or Memory
- 🔄 [Token Refresh](docs/token-refresh.md) - Automatic refresh strategies
- 📱 [Swift/iOS Integration](docs/swift-integration.md) - XCFramework usage

---

## 💡 Why Schlussel?

### Before Schlussel 😫
```rust
// 50+ lines of boilerplate
// Manual token expiration checking
// Race conditions with multiple processes
// Plaintext tokens in files
// Complex OAuth flow management
```

### With Schlussel 🎉
```rust
// 3 lines total
let storage = Arc::new(SecureStorage::new("app").unwrap());
let config = OAuthConfig::github("client-id", Some("repo"));
let token = OAuthClient::new(config, storage).authorize_device().unwrap();
```

---

## 🎯 Use Cases

✅ CLI tools that need GitHub/GitLab API access  
✅ Build tools that integrate with cloud services  
✅ Developer tools with OAuth authentication  
✅ Cross-platform desktop applications  
✅ CI/CD tools with secure credential management  

---

## 🏗️ Architecture

```
┌─────────────────┐
│   Your CLI App  │
└────────┬────────┘
         │
    ┌────▼─────┐
    │ Schlussel│
    └────┬─────┘
         │
    ┌────▼────────────────────────┐
    │  Storage Backend            │
    ├─────────────────────────────┤
    │ SecureStorage (OS Keyring)  │ ← Recommended
    │ FileStorage   (JSON files)  │
    │ MemoryStorage (In-memory)   │
    └─────────────────────────────┘
```

---

## 🌟 Highlights

### 🔐 Secure by Default
Tokens stored in **OS credential manager** (Keychain on macOS, Credential Manager on Windows, libsecret on Linux)

### 🎨 Provider Presets
```rust
OAuthConfig::github("id", Some("repo"))      // GitHub
OAuthConfig::google("id", Some("email"))     // Google
OAuthConfig::microsoft("id", "common", None) // Microsoft
OAuthConfig::gitlab("id", None, None)        // GitLab
OAuthConfig::tuist("id", None, None)         // Tuist
```

### ⚡ Automatic Token Refresh
```rust
let refresher = TokenRefresher::new(client);
let token = refresher.get_valid_token("key").unwrap();
// Auto-refreshes if expired!
```

### 🔄 Cross-Process Safe
Multiple processes can safely refresh the same token without race conditions

---

## 📦 Examples

Check out [examples/](examples/) for working code:

- 🐙 [GitHub Device Flow](examples/github_device_flow.rs)
- 🌐 [GitHub with Callback](examples/github_callback.rs)
- 🔄 [Token Refresh](examples/token_refresh.rs)
- ⚡ [Automatic Refresh](examples/automatic_refresh.rs)
- 🔐 [Secure Storage](examples/secure_storage.rs)
- 🔀 [Cross-Process Refresh](examples/cross_process_refresh.rs)

---

## 🤝 Contributing

Contributions welcome! Please ensure:
- ✅ Tests pass: `cargo test`
- ✅ Code formatted: `cargo fmt`
- ✅ Clippy clean: `cargo clippy`

---

## 📄 License

See [LICENSE](LICENSE) for details.

---

## 🔗 Links

- 📚 [Documentation](docs/README.md)
- 🐛 [Issues](https://github.com/tuist/schlussel/issues)
- 🔄 [Changelog](CHANGELOG.md)
- 📖 [API Docs](https://docs.rs/schlussel)

---

**Made with 💙 by the Tuist team**
