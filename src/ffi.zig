//! C FFI bindings for Schlussel OAuth library
//!
//! This module provides C-compatible functions for integrating Schlussel
//! with languages like Swift, Objective-C, C, and others that can call C functions.
//!
//! ## Memory Management
//!
//! - All returned pointers must be freed using the corresponding `*_free` functions
//! - Strings returned by accessor functions must be freed with `schlussel_string_free`
//! - NULL checks should be performed on all returned pointers
//!
//! ## Error Handling
//!
//! - Functions that can fail return NULL pointers or error codes
//! - Use the `SchlusselError` enum values to check specific errors

const std = @import("std");
const Allocator = std.mem.Allocator;

const session = @import("session.zig");
const oauth = @import("oauth.zig");
const error_types = @import("error.zig");
const registration = @import("registration.zig");

const Token = session.Token;
const MemoryStorage = session.MemoryStorage;
const FileStorage = session.FileStorage;
const SecureStorage = session.SecureStorage;
const OAuthConfig = oauth.OAuthConfig;
const OAuthClient = oauth.OAuthClient;
const ClientMetadata = registration.ClientMetadata;
const ClientRegistrationResponse = registration.ClientRegistrationResponse;
const DynamicRegistration = registration.DynamicRegistration;

/// Allocator for FFI operations
/// Note: Zig's GeneralPurposeAllocator is internally thread-safe, so no external mutex is needed.
/// Each allocation/free operation is atomic with respect to other threads.
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

fn getAllocator() std.mem.Allocator {
    return gpa.allocator();
}

/// Opaque client handle
pub const SchlusselClient = extern struct {
    client: *OAuthClient,
    storage: *anyopaque,
    storage_type: StorageType,

    const StorageType = enum(u8) {
        memory,
        file,
        secure,
    };
};

/// Opaque token handle
pub const SchlusselToken = extern struct {
    token: *Token,
};

/// Opaque dynamic registration client handle
pub const SchlusselRegistrationClient = extern struct {
    client: *DynamicRegistration,
};

/// Opaque registration response handle
pub const SchlusselRegistrationResponse = extern struct {
    response: *ClientRegistrationResponse,
};

// ============================================================================
// Client creation functions
// ============================================================================

/// Create a new OAuth client with GitHub configuration
export fn schlussel_client_new_github(
    client_id: [*c]const u8,
    scopes: [*c]const u8,
    app_name: [*c]const u8,
) ?*SchlusselClient {
    return createClient(
        OAuthConfig.github(
            std.mem.span(client_id),
            if (scopes != null) std.mem.span(scopes) else null,
        ),
        std.mem.span(app_name),
    );
}

/// Create a new OAuth client with Google configuration
export fn schlussel_client_new_google(
    client_id: [*c]const u8,
    scopes: [*c]const u8,
    app_name: [*c]const u8,
) ?*SchlusselClient {
    return createClient(
        OAuthConfig.google(
            std.mem.span(client_id),
            if (scopes != null) std.mem.span(scopes) else null,
        ),
        std.mem.span(app_name),
    );
}

/// Create a new OAuth client with custom configuration
export fn schlussel_client_new(
    client_id: [*c]const u8,
    authorization_endpoint: [*c]const u8,
    token_endpoint: [*c]const u8,
    redirect_uri: [*c]const u8,
    scopes: [*c]const u8,
    device_authorization_endpoint: [*c]const u8,
) ?*SchlusselClient {
    const config = OAuthConfig{
        .client_id = std.mem.span(client_id),
        .authorization_endpoint = std.mem.span(authorization_endpoint),
        .token_endpoint = std.mem.span(token_endpoint),
        .redirect_uri = std.mem.span(redirect_uri),
        .scope = if (scopes != null) std.mem.span(scopes) else null,
        .device_authorization_endpoint = if (device_authorization_endpoint != null)
            std.mem.span(device_authorization_endpoint)
        else
            null,
    };

    return createClientWithMemoryStorage(config);
}

fn createClient(config: OAuthConfig, app_name: []const u8) ?*SchlusselClient {
    const allocator = getAllocator();

    // Try to create secure storage, fall back to file storage
    const storage = SecureStorage.init(allocator, app_name) catch {
        return createClientWithFileStorage(config, app_name);
    };

    const storage_ptr = allocator.create(SecureStorage) catch return null;
    storage_ptr.* = storage;

    const client_ptr = allocator.create(OAuthClient) catch {
        allocator.destroy(storage_ptr);
        return null;
    };
    client_ptr.* = OAuthClient.init(allocator, config, storage_ptr.storage());

    const handle = allocator.create(SchlusselClient) catch {
        allocator.destroy(client_ptr);
        allocator.destroy(storage_ptr);
        return null;
    };
    handle.* = .{
        .client = client_ptr,
        .storage = storage_ptr,
        .storage_type = .secure,
    };

    return handle;
}

fn createClientWithFileStorage(config: OAuthConfig, app_name: []const u8) ?*SchlusselClient {
    const allocator = getAllocator();

    const storage = FileStorage.init(allocator, app_name) catch return null;

    const storage_ptr = allocator.create(FileStorage) catch return null;
    storage_ptr.* = storage;

    const client_ptr = allocator.create(OAuthClient) catch {
        allocator.destroy(storage_ptr);
        return null;
    };
    client_ptr.* = OAuthClient.init(allocator, config, storage_ptr.storage());

    const handle = allocator.create(SchlusselClient) catch {
        allocator.destroy(client_ptr);
        allocator.destroy(storage_ptr);
        return null;
    };
    handle.* = .{
        .client = client_ptr,
        .storage = storage_ptr,
        .storage_type = .file,
    };

    return handle;
}

fn createClientWithMemoryStorage(config: OAuthConfig) ?*SchlusselClient {
    const allocator = getAllocator();

    const storage = MemoryStorage.init(allocator);

    const storage_ptr = allocator.create(MemoryStorage) catch return null;
    storage_ptr.* = storage;

    const client_ptr = allocator.create(OAuthClient) catch {
        allocator.destroy(storage_ptr);
        return null;
    };
    client_ptr.* = OAuthClient.init(allocator, config, storage_ptr.storage());

    const handle = allocator.create(SchlusselClient) catch {
        allocator.destroy(client_ptr);
        allocator.destroy(storage_ptr);
        return null;
    };
    handle.* = .{
        .client = client_ptr,
        .storage = storage_ptr,
        .storage_type = .memory,
    };

    return handle;
}

/// Free an OAuth client
///
/// Note: Cleanup order is important - client must be freed before storage
/// because the client holds a reference to the storage interface.
export fn schlussel_client_free(client: ?*SchlusselClient) void {
    const handle = client orelse return;
    const allocator = getAllocator();

    // First, deinit the client (this doesn't use storage, just cleans up http_client if any)
    handle.client.deinit();

    // Then free the storage (while client pointer still exists but is deinitialized)
    switch (handle.storage_type) {
        .memory => {
            const storage: *MemoryStorage = @ptrCast(@alignCast(handle.storage));
            storage.deinit();
            allocator.destroy(storage);
        },
        .file => {
            const storage: *FileStorage = @ptrCast(@alignCast(handle.storage));
            storage.deinit();
            allocator.destroy(storage);
        },
        .secure => {
            const storage: *SecureStorage = @ptrCast(@alignCast(handle.storage));
            storage.deinit();
            allocator.destroy(storage);
        },
    }

    // Finally, free the client struct and the handle
    allocator.destroy(handle.client);
    allocator.destroy(handle);
}

// ============================================================================
// Authorization functions
// ============================================================================

/// Perform Device Code Flow authorization
export fn schlussel_authorize_device(client: ?*SchlusselClient) ?*SchlusselToken {
    const handle = client orelse return null;
    const allocator = getAllocator();

    var token = handle.client.authorizeDevice() catch return null;

    const token_ptr = allocator.create(Token) catch {
        token.deinit();
        return null;
    };
    token_ptr.* = token;

    const token_handle = allocator.create(SchlusselToken) catch {
        token.deinit();
        allocator.destroy(token_ptr);
        return null;
    };
    token_handle.* = .{ .token = token_ptr };

    return token_handle;
}

/// Perform Authorization Code Flow with callback server
export fn schlussel_authorize(client: ?*SchlusselClient) ?*SchlusselToken {
    const handle = client orelse return null;
    const allocator = getAllocator();

    var token = handle.client.authorize() catch return null;

    const token_ptr = allocator.create(Token) catch {
        token.deinit();
        return null;
    };
    token_ptr.* = token;

    const token_handle = allocator.create(SchlusselToken) catch {
        token.deinit();
        allocator.destroy(token_ptr);
        return null;
    };
    token_handle.* = .{ .token = token_ptr };

    return token_handle;
}

// ============================================================================
// Token storage operations
// ============================================================================

/// Save a token to storage
export fn schlussel_save_token(
    client: ?*SchlusselClient,
    key: [*c]const u8,
    token: ?*SchlusselToken,
) c_int {
    const handle = client orelse return 1; // SCHLUSSEL_ERROR_INVALID_PARAMETER
    const token_handle = token orelse return 1;

    handle.client.saveToken(std.mem.span(key), token_handle.token.*) catch {
        return 2; // SCHLUSSEL_ERROR_STORAGE
    };

    return 0; // SCHLUSSEL_OK
}

/// Get a token from storage
export fn schlussel_get_token(
    client: ?*SchlusselClient,
    key: [*c]const u8,
) ?*SchlusselToken {
    const handle = client orelse return null;
    const allocator = getAllocator();

    var token = (handle.client.getToken(std.mem.span(key)) catch return null) orelse return null;

    const token_ptr = allocator.create(Token) catch {
        token.deinit();
        return null;
    };
    token_ptr.* = token;

    const token_handle = allocator.create(SchlusselToken) catch {
        token.deinit();
        allocator.destroy(token_ptr);
        return null;
    };
    token_handle.* = .{ .token = token_ptr };

    return token_handle;
}

/// Delete a token from storage
export fn schlussel_delete_token(
    client: ?*SchlusselClient,
    key: [*c]const u8,
) c_int {
    const handle = client orelse return 1;

    handle.client.deleteToken(std.mem.span(key)) catch {
        return 2; // SCHLUSSEL_ERROR_STORAGE
    };

    return 0; // SCHLUSSEL_OK
}

/// Refresh an access token using a refresh token
export fn schlussel_refresh_token(
    client: ?*SchlusselClient,
    refresh_token: [*c]const u8,
) ?*SchlusselToken {
    const handle = client orelse return null;
    const allocator = getAllocator();

    var token = handle.client.refreshToken(std.mem.span(refresh_token)) catch return null;

    const token_ptr = allocator.create(Token) catch {
        token.deinit();
        return null;
    };
    token_ptr.* = token;

    const token_handle = allocator.create(SchlusselToken) catch {
        token.deinit();
        allocator.destroy(token_ptr);
        return null;
    };
    token_handle.* = .{ .token = token_ptr };

    return token_handle;
}

// ============================================================================
// Token accessors
// ============================================================================

/// Get the access token string
export fn schlussel_token_get_access_token(token: ?*SchlusselToken) ?[*:0]u8 {
    const handle = token orelse return null;
    return dupeToC(handle.token.access_token);
}

/// Get the refresh token string
export fn schlussel_token_get_refresh_token(token: ?*SchlusselToken) ?[*:0]u8 {
    const handle = token orelse return null;
    const rt = handle.token.refresh_token orelse return null;
    return dupeToC(rt);
}

/// Get the token type string
export fn schlussel_token_get_token_type(token: ?*SchlusselToken) ?[*:0]u8 {
    const handle = token orelse return null;
    return dupeToC(handle.token.token_type);
}

/// Get the scope string
export fn schlussel_token_get_scope(token: ?*SchlusselToken) ?[*:0]u8 {
    const handle = token orelse return null;
    const scope = handle.token.scope orelse return null;
    return dupeToC(scope);
}

/// Check if the token is expired
export fn schlussel_token_is_expired(token: ?*SchlusselToken) c_int {
    const handle = token orelse return -1;
    return if (handle.token.isExpired()) 1 else 0;
}

/// Get the token expiration timestamp
export fn schlussel_token_get_expires_at(token: ?*SchlusselToken) u64 {
    const handle = token orelse return 0;
    return handle.token.expires_at orelse 0;
}

/// Free a token
export fn schlussel_token_free(token: ?*SchlusselToken) void {
    const handle = token orelse return;
    const allocator = getAllocator();
    handle.token.deinit();
    allocator.destroy(handle.token);
    allocator.destroy(handle);
}

// ============================================================================
// String operations
// ============================================================================

/// Free a string returned by Schlussel functions
export fn schlussel_string_free(str: ?[*:0]u8) void {
    const s = str orelse return;
    const allocator = getAllocator();
    // Calculate length to free
    var len: usize = 0;
    while (s[len] != 0) : (len += 1) {}
    allocator.free(s[0 .. len + 1]);
}

// ============================================================================
// Helper functions
// ============================================================================

fn dupeToC(str: []const u8) ?[*:0]u8 {
    const allocator = getAllocator();
    const result = allocator.allocSentinel(u8, str.len, 0) catch return null;
    @memcpy(result, str);
    return result;
}

// ============================================================================
// Dynamic Client Registration functions
// ============================================================================

/// Create a new dynamic registration client
export fn schlussel_registration_new(endpoint: [*c]const u8) ?*SchlusselRegistrationClient {
    const allocator = getAllocator();

    var client = DynamicRegistration.init(allocator, std.mem.span(endpoint)) catch return null;

    const client_ptr = allocator.create(DynamicRegistration) catch {
        client.deinit();
        return null;
    };
    client_ptr.* = client;

    const handle = allocator.create(SchlusselRegistrationClient) catch {
        client.deinit();
        allocator.destroy(client_ptr);
        return null;
    };
    handle.* = .{ .client = client_ptr };

    return handle;
}

/// Free a registration client
export fn schlussel_registration_free(client: ?*SchlusselRegistrationClient) void {
    const handle = client orelse return;
    const allocator = getAllocator();

    handle.client.deinit();
    allocator.destroy(handle.client);
    allocator.destroy(handle);
}

/// Register a new OAuth client
///
/// Parameters:
/// - client: Registration client handle
/// - redirect_uris: Array of redirect URI strings
/// - redirect_uris_count: Number of redirect URIs
/// - client_name: Human-readable client name (may be NULL)
/// - grant_types: Comma-separated grant types (may be NULL)
/// - response_types: Comma-separated response types (may be NULL)
/// - scope: OAuth scope (may be NULL)
/// - token_auth_method: Token endpoint auth method (may be NULL)
///
/// Returns: Registration response handle on success, NULL on error
export fn schlussel_register_client(
    reg_client: ?*SchlusselRegistrationClient,
    redirect_uris: [*c]const [*c]const u8,
    redirect_uris_count: usize,
    client_name: [*c]const u8,
    grant_types: [*c]const u8,
    response_types: [*c]const u8,
    scope: [*c]const u8,
    token_auth_method: [*c]const u8,
) ?*SchlusselRegistrationResponse {
    const handle = reg_client orelse return null;
    const allocator = getAllocator();

    // Create metadata
    var metadata = ClientMetadata.init(allocator) catch return null;
    errdefer metadata.deinit();

    // Set redirect URIs
    const uris_ptr: [*]const [*:0]const u8 = @ptrCast(redirect_uris);
    const uris_slice = uris_ptr[0..redirect_uris_count];
    var redirect_uris_list: std.ArrayList([]const u8) = .empty;
    defer {
        for (redirect_uris_list.items) |uri| allocator.free(uri);
        redirect_uris_list.deinit(allocator);
    }

    for (uris_slice) |uri_c_str| {
        const uri_dup = allocator.dupe(u8, std.mem.span(uri_c_str)) catch return null;
        redirect_uris_list.append(allocator, uri_dup) catch return null;
    }
    metadata.redirect_uris = allocator.dupe([]const u8, redirect_uris_list.items) catch return null;

    // Set optional fields
    if (client_name != null) {
        metadata.client_name = std.mem.span(client_name);
    }

    if (grant_types != null) {
        metadata.grant_types = parseCommaSeparated(allocator, std.mem.span(grant_types)) catch return null;
    }

    if (response_types != null) {
        metadata.response_types = parseCommaSeparated(allocator, std.mem.span(response_types)) catch return null;
    }

    if (scope != null) {
        metadata.scope = std.mem.span(scope);
    }

    if (token_auth_method != null) {
        metadata.token_endpoint_auth_method = std.mem.span(token_auth_method);
    }

    // Register the client
    var response = handle.client.register(metadata) catch return null;

    const response_ptr = allocator.create(ClientRegistrationResponse) catch {
        response.deinit();
        return null;
    };
    response_ptr.* = response;

    const response_handle = allocator.create(SchlusselRegistrationResponse) catch {
        response.deinit();
        allocator.destroy(response_ptr);
        return null;
    };
    response_handle.* = .{ .response = response_ptr };

    return response_handle;
}

/// Free a registration response
export fn schlussel_registration_response_free(response: ?*SchlusselRegistrationResponse) void {
    const handle = response orelse return;
    const allocator = getAllocator();

    handle.response.deinit();
    allocator.destroy(handle.response);
    allocator.destroy(handle);
}

/// Get the client ID from a registration response
export fn schlussel_registration_response_get_client_id(response: ?*SchlusselRegistrationResponse) ?[*:0]u8 {
    const handle = response orelse return null;
    return dupeToC(handle.response.client_id);
}

/// Get the client secret from a registration response (may be NULL)
export fn schlussel_registration_response_get_client_secret(response: ?*SchlusselRegistrationResponse) ?[*:0]u8 {
    const handle = response orelse return null;
    const secret = handle.response.client_secret orelse return null;
    return dupeToC(secret);
}

/// Get the client ID issued at timestamp (Unix timestamp, 0 if not set)
export fn schlussel_registration_response_get_client_id_issued_at(response: ?*SchlusselRegistrationResponse) i64 {
    const handle = response orelse return 0;
    return handle.response.client_id_issued_at orelse 0;
}

/// Get the client secret expires at timestamp (Unix timestamp, 0 if never expires)
export fn schlussel_registration_response_get_client_secret_expires_at(response: ?*SchlusselRegistrationResponse) i64 {
    const handle = response orelse return 0;
    return handle.response.client_secret_expires_at orelse 0;
}

/// Get the registration access token (may be NULL)
export fn schlussel_registration_response_get_registration_access_token(response: ?*SchlusselRegistrationResponse) ?[*:0]u8 {
    const handle = response orelse return null;
    const token = handle.response.registration_access_token orelse return null;
    return dupeToC(token);
}

/// Get the registration client URI (may be NULL)
export fn schlussel_registration_response_get_registration_client_uri(response: ?*SchlusselRegistrationResponse) ?[*:0]u8 {
    const handle = response orelse return null;
    const uri = handle.response.registration_client_uri orelse return null;
    return dupeToC(uri);
}

/// Helper function to parse comma-separated values
fn parseCommaSeparated(allocator: Allocator, str: []const u8) ![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    defer {
        for (list.items) |item| allocator.free(item);
        list.deinit(allocator);
    }

    var iter = std.mem.splitScalar(u8, str, ',');
    while (iter.next()) |item| {
        const trimmed = std.mem.trim(u8, item, " ");
        if (trimmed.len > 0) {
            try list.append(allocator, try allocator.dupe(u8, trimmed));
        }
    }

    // Clone the list since the ArrayList will be freed
    const result = try allocator.dupe([]const u8, list.items);
    return result;
}

test "FFI client creation and cleanup" {
    const client = schlussel_client_new_github(
        "test-client-id",
        "repo user",
        "test-app",
    );

    // Client might be null in test environment (no keyring), that's OK
    if (client) |c| {
        schlussel_client_free(c);
    }
}

test "FFI token accessors with null safety" {
    // All accessor functions should handle null gracefully
    try std.testing.expect(schlussel_token_get_access_token(null) == null);
    try std.testing.expect(schlussel_token_get_refresh_token(null) == null);
    try std.testing.expect(schlussel_token_get_token_type(null) == null);
    try std.testing.expect(schlussel_token_get_scope(null) == null);
    try std.testing.expect(schlussel_token_is_expired(null) == -1);
    try std.testing.expect(schlussel_token_get_expires_at(null) == 0);
}

test "FFI string free with null" {
    // Should not crash with null
    schlussel_string_free(null);
}

test "FFI token free with null" {
    // Should not crash with null
    schlussel_token_free(null);
}

test "FFI client free with null" {
    // Should not crash with null
    schlussel_client_free(null);
}
