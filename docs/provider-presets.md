# 🔌 Provider Presets

Pre-configured OAuth for popular services - just add your client ID!

## GitHub 🐙

```rust
let config = OAuthConfig::github("client-id", Some("repo user"));
```

**Features:**
- ✅ Device Code Flow
- ✅ Authorization Code Flow

**Common Scopes:** `repo`, `user`, `gist`, `notifications`, `read:org`

**Setup:** Create OAuth App at https://github.com/settings/developers

## Google 🔵

```rust
let config = OAuthConfig::google(
    "client-id.apps.googleusercontent.com",
    Some("openid email profile")
);
```

**Features:**
- ✅ Device Code Flow
- ✅ Authorization Code Flow

**Common Scopes:** `openid`, `email`, `profile`, `https://www.googleapis.com/auth/drive`

**Setup:** Create OAuth client at https://console.cloud.google.com/apis/credentials

## Microsoft/Azure AD 🔷

```rust
let config = OAuthConfig::microsoft(
    "client-id",
    "common",  // or your tenant ID
    Some("User.Read Mail.Read")
);
```

**Features:**
- ✅ Device Code Flow
- ✅ Authorization Code Flow
- ✅ Multi-tenant and single-tenant support

**Common Scopes:** `User.Read`, `Mail.Read`, `Calendars.Read`, `Files.ReadWrite`

**Tenant Values:**
- `"common"` - Multi-tenant (any Microsoft account)
- `"organizations"` - Any organization account
- `"consumers"` - Personal Microsoft accounts only
- `"<tenant-id>"` - Specific tenant/directory

**Setup:** Register app at https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps

## GitLab 🦊

```rust
// GitLab.com
let config = OAuthConfig::gitlab("client-id", Some("read_user api"), None);

// Self-hosted
let config = OAuthConfig::gitlab(
    "client-id",
    Some("read_user"),
    Some("https://gitlab.mycompany.com")
);
```

**Features:**
- ✅ Authorization Code Flow
- ✅ Self-hosted instance support
- ⚠️ No Device Code Flow (not yet supported by GitLab)

**Common Scopes:** `read_user`, `read_api`, `write_repository`, `read_registry`

**Setup:** Create OAuth application in GitLab Settings → Applications

## Tuist 🎯

```rust
// Tuist Cloud
let config = OAuthConfig::tuist("client-id", None, None);

// Self-hosted
let config = OAuthConfig::tuist(
    "client-id",
    None,
    Some("https://tuist.mycompany.com")
);
```

**Features:**
- ✅ Device Code Flow
- ✅ Authorization Code Flow
- ✅ Self-hosted instance support

---

## Custom OAuth Provider

Need a provider that's not listed? Easy:

```rust
let config = OAuthConfig {
    client_id: "your-client-id".to_string(),
    authorization_endpoint: "https://provider.com/oauth/authorize".to_string(),
    token_endpoint: "https://provider.com/oauth/token".to_string(),
    redirect_uri: "http://127.0.0.1:8080/callback".to_string(),
    scope: Some("read write".to_string()),
    device_authorization_endpoint: Some("https://provider.com/oauth/device/code".to_string()),
};
```

---

## 🔗 Provider Comparison

| Provider | Device Flow | Callback Flow | Self-Hosted |
|----------|------------|---------------|-------------|
| GitHub | ✅ | ✅ | ❌ |
| Google | ✅ | ✅ | ❌ |
| Microsoft | ✅ | ✅ | ❌ |
| GitLab | ❌ | ✅ | ✅ |
| Tuist | ✅ | ✅ | ✅ |

---

**Next:** Check out [Storage Backends](storage-backends.md) to choose where to store your tokens
