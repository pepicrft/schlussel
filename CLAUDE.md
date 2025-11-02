# Claude Instructions for Schlussel

## Project Overview

Schlussel is a cross-platform OAuth 2.0 library with PKCE and Device Code Flow support, written in Rust. It's specifically designed for command-line applications and provides secure token storage using OS credential managers.

## Core Architecture

### Key Modules

1. **PKCE Module** (`src/pkce.rs`)
   - Generates cryptographically secure code verifiers and challenges
   - Uses SHA256 for challenge generation
   - Base64 URL-safe encoding without padding

2. **Session Management** (`src/session.rs`)
   - Trait-based storage interface (`SessionStorage`)
   - Three built-in backends: `SecureStorage`, `FileStorage`, `MemoryStorage`
   - Thread-safe with `parking_lot::RwLock`
   - Domain-based file organization

3. **OAuth Flow** (`src/oauth.rs`)
   - Device Code Flow (RFC 8628) - primary for CLI apps
   - Authorization Code Flow with PKCE
   - Automatic browser opening and callback handling
   - Token refresh with HTTP client (`reqwest`)
   - Provider presets (GitHub, Google, Microsoft, GitLab, Tuist)

4. **Token Refresher** (`src/oauth.rs`)
   - In-process locking (threads)
   - Cross-process locking (file-based with `fs2`)
   - Automatic token refresh (`get_valid_token`)
   - Proactive refresh with thresholds

5. **Callback Server** (`src/callback.rs`)
   - Local HTTP server for OAuth redirects
   - Random port assignment
   - HTML success/error pages

6. **Cross-Process Locking** (`src/lock.rs`)
   - File-based locks using `fs2`
   - RAII lock guards
   - Check-then-refresh pattern

7. **FFI Layer** (`src/ffi.rs`)
   - C-compatible API for Swift/Objective-C
   - Opaque pointers for type safety
   - Error codes instead of Result types

## Documentation Maintenance 📚

**CRITICAL**: Documentation must ALWAYS be kept in sync with code changes!

### Documentation Structure

- **`README.md`** - Simple, emoji-rich overview with links to docs/
- **`docs/README.md`** - Documentation index
- **`docs/*.md`** - Individual topic documentation

### Rules for Code Changes

When you modify code, you MUST update documentation:

1. **Adding a new feature:**
   - Update relevant `docs/*.md` file
   - Add to `docs/README.md` index if it's a major feature
   - Update main `README.md` if it's a key feature
   - Add example to `examples/` directory

2. **Changing an API:**
   - Update all code examples in `docs/`
   - Update `README.md` if the API is shown there
   - Update inline doc comments (`///`)
   - Update examples in `examples/`

3. **Adding dependencies:**
   - Document why in relevant `docs/*.md`
   - Update platform requirements if needed

4. **Deprecating features:**
   - Add deprecation notices to docs
   - Provide migration guides

### Documentation Checklist

Before completing any task, verify:
- ✅ All code examples in docs still compile
- ✅ API signatures in docs match actual code
- ✅ New features are documented
- ✅ README.md links to relevant docs
- ✅ Examples are up to date

### Keep It Simple

- **README.md**: Short, visual, emoji-rich, links to docs/
- **docs/**: Detailed guides, keep each file focused on one topic
- **Inline docs**: Comprehensive, with examples
- **Examples**: Working code that demonstrates features

## Development Guidelines

### Code Style

- Follow Rust standard conventions (`cargo fmt`)
- Use `const` by default
- Prefer `?` for error propagation
- Document public APIs with doc comments (`///`)
- Add examples to doc comments

### Testing

- Unit tests inline in modules
- Integration tests in `tests/`
- Run: `cargo test`
- All tests must pass before committing
- Add tests for new features

### Building

- Development: `cargo build`
- Release: `cargo build --release`
- Examples: `cargo run --example <name>`
- All targets: `mise run build`

### CI Requirements

All PRs must pass:
- ✅ Tests on Ubuntu, macOS, Windows
- ✅ `cargo fmt --check`
- ✅ `cargo clippy -- -D warnings`

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

- `get_valid_token()` eliminates manual expiration checking
- Proactive refresh with configurable thresholds
- Cross-process safe when using `with_file_locking()`

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

1. Add method to `OAuthConfig` impl in `src/oauth.rs`
2. Add test to verify endpoints
3. Add doctest example
4. Update `docs/provider-presets.md`
5. Update `README.md` if it's a major provider

### Adding a New Storage Backend

1. Implement `SessionStorage` trait in `src/session.rs`
2. Add to prelude exports in `src/lib.rs`
3. Add tests
4. Add example to `examples/`
5. Document in `docs/storage-backends.md`

### Adding FFI Functions

1. Add to `src/ffi.rs` with `#[no_mangle]` and `extern "C"`
2. Update `include/schlussel.h`
3. Update Swift wrapper if applicable
4. Test on all platforms

## Security Considerations

1. **Secure Storage**: Always recommend `SecureStorage` for production
2. **PKCE Required**: Never allow non-PKCE flows
3. **State Validation**: Always verify state parameter
4. **HTTPS Only**: Validate endpoints use HTTPS (except localhost)
5. **Token Expiration**: Use `get_valid_token()` for automatic checking
6. **Cross-Process Safety**: Use `with_file_locking()` when multiple processes might run

## Platform-Specific Notes

### macOS
- SecureStorage uses Keychain
- XCFramework support for Swift/iOS
- Keyring tests may skip in some environments

### Windows
- SecureStorage uses Credential Manager
- File locking uses different error codes (handle error 33)

### Linux
- SecureStorage requires libsecret
- XDG Base Directory specification for file paths

## API Stability

### Stable (don't break without major version)
- Public structs and their fields
- `SessionStorage` trait methods
- FFI function signatures
- Provider preset methods

### Can Change (minor versions)
- Internal implementation details
- Private functions
- Error message formats

## Testing Strategy

1. **Unit tests**: Test individual components
2. **Integration tests**: Test full OAuth flows (mock when needed)
3. **Doctest examples**: Ensure documentation code compiles
4. **Platform-specific**: Test file locking, keyring on each OS
5. **Graceful skipping**: Tests skip if environment doesn't support (e.g., keyring in CI)

## References

- [RFC 7636: PKCE](https://tools.ietf.org/html/rfc7636)
- [RFC 6749: OAuth 2.0](https://tools.ietf.org/html/rfc6749)
- [RFC 8628: Device Code Flow](https://tools.ietf.org/html/rfc8628)
- [RFC 8252: OAuth 2.0 for Native Apps](https://tools.ietf.org/html/rfc8252)
