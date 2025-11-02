# 💾 Storage Backends

Choose where and how to store your OAuth tokens.

---

## 🔒 SecureStorage (Recommended for Production)

**Uses OS credential manager - tokens are encrypted!**

```rust
let storage = Arc::new(SecureStorage::new("my-app").unwrap());
```

**Platform Support:**
- 🍎 **macOS**: Keychain
- 🪟 **Windows**: Credential Manager
- 🐧 **Linux**: Secret Service API (libsecret)

**Security:**
- ✅ Tokens encrypted at rest by OS
- ✅ OS-level access control
- ✅ Not visible in file system
- ✅ Automatic key management
- ✅ Integration with OS security features

**Best for:** Production applications, sensitive tokens

---

## 📁 FileStorage (Good for Development)

**Stores tokens in JSON files**

```rust
let storage = Arc::new(FileStorage::new("my-app").unwrap());
```

**Storage Location:**
- 🐧 **Linux/macOS**: `~/.local/share/my-app/`
- 🪟 **Windows**: `%APPDATA%\my-app\`

**Features:**
- ✅ Easy to inspect and debug
- ✅ Domain-based organization
- ✅ XDG Base Directory compliant
- ⚠️ **Warning**: Tokens stored as plain JSON

**Best for:** Development, debugging, testing

---

## 💭 MemoryStorage (For Testing)

**In-memory only - data lost on exit**

```rust
let storage = Arc::new(MemoryStorage::new());
```

**Features:**
- ✅ Fast
- ✅ Thread-safe
- ✅ No filesystem access needed
- ❌ Not persistent

**Best for:** Unit tests, temporary use

---

## 📊 Comparison

| Feature | SecureStorage | FileStorage | MemoryStorage |
|---------|--------------|-------------|---------------|
| Encryption | ✅ OS-encrypted | ❌ Plain text | ❌ None |
| Persistence | ✅ Yes | ✅ Yes | ❌ No |
| Filesystem | ❌ Hidden | ✅ Visible | ❌ N/A |
| Security | 🔒 High | ⚠️ Low | ⚠️ Low |
| Use Case | 🚀 Production | 🛠️ Dev | 🧪 Testing |

---

## 🔧 Custom Storage

Implement your own storage by implementing the `SessionStorage` trait:

```rust
use schlussel::session::{SessionStorage, Session, Token};

pub struct MyStorage {
    // Your storage implementation
}

impl SessionStorage for MyStorage {
    fn save_session(&self, state: &str, session: Session) -> Result<(), String> {
        // Your implementation
    }
    
    fn get_session(&self, state: &str) -> Result<Option<Session>, String> {
        // Your implementation
    }
    
    // ... implement other methods
}
```

**Ideas:**
- SQLite database
- Redis/cloud storage
- Encrypted file storage with custom keys
- Database with audit logging

See [Custom Storage Guide](custom-storage.md) for more details.

---

**Next:** Learn about [Token Refresh](token-refresh.md) strategies
