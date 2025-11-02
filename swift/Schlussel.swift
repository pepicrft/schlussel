import Foundation

/// Swift wrapper for Schlussel OAuth library
public class SchlusselClient {
    private let handle: OpaquePointer

    /// Create a new OAuth client for GitHub
    ///
    /// - Parameters:
    ///   - clientId: Your GitHub OAuth App client ID
    ///   - scopes: Optional scopes (e.g., "repo user")
    ///   - appName: Application name for secure storage
    public init?(githubClientId clientId: String, scopes: String? = nil, appName: String) {
        guard let handle = schlussel_client_new_github(
            clientId,
            scopes,
            appName
        ) else {
            return nil
        }
        self.handle = handle
    }

    deinit {
        schlussel_client_free(handle)
    }

    /// Authorize using Device Code Flow
    ///
    /// This will:
    /// 1. Display a URL and code to the user
    /// 2. Open the browser automatically
    /// 3. Poll for authorization
    /// 4. Return the access token
    ///
    /// - Returns: Token if authorization succeeds, nil otherwise
    public func authorizeDevice() -> SchlusselToken? {
        guard let tokenHandle = schlussel_authorize_device(handle) else {
            return nil
        }
        return SchlusselToken(handle: tokenHandle)
    }

    /// Save a token with a key
    ///
    /// - Parameters:
    ///   - key: Token key (e.g., "github.com:user")
    ///   - token: The token to save
    /// - Returns: true if successful, false otherwise
    public func saveToken(key: String, token: SchlusselToken) -> Bool {
        let error = schlussel_save_token(handle, key, token.handle)
        return error == SCHLUSSEL_OK
    }
}

/// Represents an OAuth token
public class SchlusselToken {
    fileprivate let handle: OpaquePointer

    fileprivate init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        schlussel_token_free(handle)
    }

    /// Get the access token string
    public var accessToken: String? {
        guard let cString = schlussel_token_get_access_token(handle) else {
            return nil
        }
        defer { schlussel_string_free(cString) }
        return String(cString: cString)
    }

    /// Check if the token is expired
    public var isExpired: Bool {
        return schlussel_token_is_expired(handle) != 0
    }
}

/// Example Usage:
///
/// ```swift
/// // Create client
/// guard let client = SchlusselClient(
///     githubClientId: "your-client-id",
///     scopes: "repo user",
///     appName: "my-app"
/// ) else {
///     print("Failed to create client")
///     return
/// }
///
/// // Authorize
/// guard let token = client.authorizeDevice() else {
///     print("Authorization failed")
///     return
/// }
///
/// // Save token
/// _ = client.saveToken(key: "github.com:user", token: token)
///
/// // Use token
/// if let accessToken = token.accessToken {
///     print("Access token: \\(accessToken)")
/// }
/// ```
