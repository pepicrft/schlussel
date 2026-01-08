# Claude Instructions for Schlussel

## Project Overview

Schlussel is a cross-platform OAuth 2.0 library with PKCE and Device Code Flow support, written in Zig. It's specifically designed for command-line applications and provides secure token storage using OS credential managers.

## Core Architecture

### Key Modules

1. **PKCE Module** (`src/pkce.zig`)
   - Generates cryptographically secure code verifiers and challenges
   - Uses SHA256 for challenge generation
   - Base64 URL-safe encoding without padding

2. **Session Management** (`src/session.zig`)
   - Interface-based storage (`SessionStorage`)
   - Three built-in backends: `SecureStorage`, `FileStorage`, `MemoryStorage`
   - Thread-safe with mutex protection
   - Domain-based file organization

3. **OAuth Flow** (`src/oauth.zig`)
   - Device Code Flow (RFC 8628) - primary for CLI apps
   - Authorization Code Flow with PKCE
   - Automatic browser opening and callback handling
   - Token refresh with HTTP client
   - Provider presets (GitHub, Google, Microsoft, GitLab, Tuist)

4. **Token Refresher** (`src/oauth.zig`)
   - In-process locking (threads)
   - Cross-process locking (file-based)
   - Automatic token refresh (`getValidToken`)
   - Proactive refresh with thresholds

5. **Callback Server** (`src/callback.zig`)
   - Local HTTP server for OAuth redirects
   - Random port assignment
   - HTML success/error pages

6. **Cross-Process Locking** (`src/lock.zig`)
   - File-based locks
   - RAII lock guards
   - Check-then-refresh pattern

7. **FFI Layer** (`src/ffi.zig`)
   - C-compatible API for Swift/Objective-C
   - Opaque pointers for type safety
   - Error codes instead of error unions

## Development Guidelines

### Code Style

- Follow Zig standard conventions (`zig fmt`)
- Use `const` by default
- Document public APIs with doc comments (`///`)
- Add examples to doc comments

### Testing

- Unit tests inline in modules
- Run: `zig build test`
- All tests must pass before committing
- Add tests for new features
- Use `std.testing.allocator` to detect memory leaks

### Building

- Development: `zig build`
- Run tests: `zig build test`
- Examples: `zig build example-github-device`
- Format: `zig fmt src/`

### CI Requirements

All PRs must pass:
- Tests on Ubuntu, macOS, Windows
- `zig fmt --check src/`

## Important Design Decisions

### 1. Security First

- **SecureStorage is default recommendation** - uses OS credential managers
- FileStorage has warnings about plaintext storage
- Always use PKCE for OAuth flows
- Cross-process locking prevents race conditions

### 2. Device Code Flow Priority

- Primary flow for CLI applications
- Simpler UX than callback server
- Works in headless/remote environments
- Falls back to callback flow when Device Code not supported

### 3. Automatic Token Refresh

- `getValidToken()` eliminates manual expiration checking
- Proactive refresh with configurable thresholds
- Cross-process safe when using file locking

### 4. Provider Presets

- One-line configuration for popular providers
- Reduces errors from manual endpoint configuration
- Self-hosted instance support where applicable

### 5. Storage Abstraction

Three built-in backends:
- **SecureStorage**: Production (OS keychain/credential manager)
- **FileStorage**: Development (JSON files)
- **MemoryStorage**: Testing (in-memory)

### 6. Cross-Process Coordination

- File-based locks at refresh level (not storage level)
- Check-then-refresh pattern to avoid redundant HTTP requests
- RAII lock guards with automatic cleanup

## Common Tasks

### Adding a New Provider Preset

1. Add method to `OAuthConfig` in `src/oauth.zig`
2. Add test to verify endpoints
3. Update README.md if it's a major provider

### Adding a New Storage Backend

1. Implement `SessionStorage` interface in `src/session.zig`
2. Add tests
3. Add example to `examples/`

### Adding FFI Functions

1. Add to `src/ffi.zig` with `export` keyword
2. Update `include/schlussel.h`
3. Test on all platforms

## Security Considerations

1. **Secure Storage**: Always recommend `SecureStorage` for production
2. **PKCE Required**: Never allow non-PKCE flows
3. **State Validation**: Always verify state parameter
4. **HTTPS Only**: Validate endpoints use HTTPS (except localhost)
5. **Token Expiration**: Use `getValidToken()` for automatic checking
6. **Cross-Process Safety**: Use file locking when multiple processes might run

## Platform-Specific Notes

### macOS
- SecureStorage uses Keychain
- XCFramework support for Swift/iOS

### Windows
- SecureStorage uses Credential Manager
- File locking uses different error codes

### Linux
- SecureStorage requires libsecret
- XDG Base Directory specification for file paths

## References

- [RFC 7636: PKCE](https://tools.ietf.org/html/rfc7636)
- [RFC 6749: OAuth 2.0](https://tools.ietf.org/html/rfc6749)
- [RFC 8628: Device Code Flow](https://tools.ietf.org/html/rfc8628)
- [RFC 8252: OAuth 2.0 for Native Apps](https://tools.ietf.org/html/rfc8252)
