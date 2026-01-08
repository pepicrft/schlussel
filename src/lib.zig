//! Schlussel - Cross-platform OAuth 2.0 library with PKCE and Device Code Flow support
//!
//! Schlussel is designed for command-line applications and provides secure token
//! storage using OS credential managers. It supports multiple OAuth providers
//! including GitHub, Google, Microsoft, GitLab, and Tuist.
//!
//! ## Features
//!
//! - **PKCE Support**: RFC 7636 compliant Proof Key for Code Exchange
//! - **Device Code Flow**: RFC 8628 compliant for headless/CLI applications
//! - **Authorization Code Flow**: Standard OAuth 2.0 with local callback server
//! - **Secure Storage**: OS-native credential managers (Keychain, Credential Manager, Secret Service)
//! - **Token Refresh**: Automatic token refresh with cross-process locking
//! - **Provider Presets**: One-line configuration for popular OAuth providers
//!
//! ## Quick Start
//!
//! ```zig
//! const schlussel = @import("schlussel");
//!
//! // Create OAuth client with GitHub preset
//! const config = schlussel.OAuthConfig.github("your-client-id", "repo user");
//! var storage = schlussel.MemoryStorage.init(allocator);
//! defer storage.deinit();
//!
//! var client = schlussel.OAuthClient.init(allocator, config, &storage);
//! defer client.deinit();
//!
//! // Perform Device Code Flow authorization
//! const token = try client.authorizeDevice();
//! ```

const std = @import("std");

// Core modules
pub const pkce = @import("pkce.zig");
pub const session = @import("session.zig");
pub const error_types = @import("error.zig");
pub const oauth = @import("oauth.zig");
pub const callback = @import("callback.zig");
pub const lock = @import("lock.zig");

// Re-export commonly used types for convenience
pub const Pkce = pkce.Pkce;
pub const Token = session.Token;
pub const Session = session.Session;
pub const SessionStorage = session.SessionStorage;
pub const MemoryStorage = session.MemoryStorage;
pub const FileStorage = session.FileStorage;
pub const SecureStorage = session.SecureStorage;
pub const OAuthError = error_types.OAuthError;
pub const OAuthConfig = oauth.OAuthConfig;
pub const OAuthClient = oauth.OAuthClient;
pub const TokenRefresher = oauth.TokenRefresher;
pub const DeviceAuthorizationResponse = oauth.DeviceAuthorizationResponse;
pub const AuthFlowResult = oauth.AuthFlowResult;
pub const CallbackServer = callback.CallbackServer;
pub const CallbackResult = callback.CallbackResult;
pub const RefreshLockManager = lock.RefreshLockManager;
pub const RefreshLock = lock.RefreshLock;

// FFI exports (only when building as library)
pub const ffi = @import("ffi.zig");

test {
    // Run all module tests
    std.testing.refAllDecls(@This());
}
