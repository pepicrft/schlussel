# 🔄 OAuth Flows Explained

Understanding when to use Device Code Flow vs Authorization Code Flow.

---

## 🎯 Device Code Flow (RFC 8628)

**Recommended for CLI applications!**

### How it Works

1. Your app requests a device code from OAuth provider
2. User sees: "Visit https://provider.com/device and enter code: ABCD-1234"
3. Browser opens automatically
4. User enters code and authorizes
5. Your app polls and receives token

### When to Use ✅

- ✅ CLI applications
- ✅ Headless/remote environments (SSH, Docker)
- ✅ Input-constrained devices
- ✅ Simplest implementation

### Pros

- No callback server needed
- Works when browser is on a different device
- Perfect for remote/SSH sessions
- Better UX for CLI tools

### Cons

- User must manually enter code (though we auto-open browser)
- Requires provider support
- Slightly slower than callback flow

### Supported Providers

- GitHub ✅
- Google ✅
- Microsoft ✅
- Tuist ✅
- GitLab ❌ (not yet)

---

## 🌐 Authorization Code Flow

**Traditional OAuth with callback**

### How it Works

1. Your app starts a local HTTP server on random port
2. Browser opens with authorization URL
3. User authorizes
4. Provider redirects to your local server
5. Your app exchanges code for token

### When to Use ✅

- ✅ When Device Code Flow isn't supported
- ✅ Desktop applications
- ✅ Local development
- ✅ Fastest flow when it works

### Pros

- Fully automated (no code entry)
- Works with any OAuth 2.0 provider
- Faster than Device Code Flow
- Standard OAuth flow

### Cons

- Requires local HTTP server
- May not work in some network environments
- Can't use when browser is on different device

---

## 🤔 Which Should I Use?

```
┌─────────────────────────────────┐
│ Is it a CLI application?        │
└───────────┬─────────────────────┘
            │ Yes
            ▼
┌─────────────────────────────────┐
│ Does provider support           │
│ Device Code Flow?               │
└───────────┬─────────────────────┘
            │ Yes
            ▼
    Use Device Code Flow! 🎯
    
    
If provider doesn't support Device Code:
    Use Authorization Code Flow 🌐
```

---

## 📝 Code Examples

### Device Code Flow

```rust
let config = OAuthConfig::github("client-id", Some("repo"));
let client = OAuthClient::new(config, storage);
let token = client.authorize_device()?;
```

### Authorization Code Flow

```rust
let config = OAuthConfig::github("client-id", Some("repo"));
let client = OAuthClient::new(config, storage);
let token = client.authorize()?;  // Starts callback server
```

---

**Next:** Check out [Provider Presets](provider-presets.md) for supported providers
