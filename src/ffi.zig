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
//! - Use `schlussel_last_error_code` / `schlussel_last_error_message` for details

const std = @import("std");
const Allocator = std.mem.Allocator;

const session = @import("session.zig");
const oauth = @import("oauth.zig");
const error_types = @import("error.zig");
const registration = @import("registration.zig");
const formulas = @import("formulas.zig");
const callback = @import("callback.zig");
const pkce = @import("pkce.zig");

const Token = session.Token;
const MemoryStorage = session.MemoryStorage;
const FileStorage = session.FileStorage;
const SecureStorage = session.SecureStorage;
const OAuthConfig = oauth.OAuthConfig;
const OAuthClient = oauth.OAuthClient;
const ClientMetadata = registration.ClientMetadata;
const ClientRegistrationResponse = registration.ClientRegistrationResponse;
const DynamicRegistration = registration.DynamicRegistration;

const ScriptContext = struct {
    authorize_url: ?[]const u8 = null,
    pkce_verifier: ?[]const u8 = null,
    state: ?[]const u8 = null,
    redirect_uri: ?[]const u8 = null,
    device_code: ?[]const u8 = null,
    user_code: ?[]const u8 = null,
    verification_uri: ?[]const u8 = null,
    verification_uri_complete: ?[]const u8 = null,
    interval: ?u64 = null,
    expires_in: ?u64 = null,
};

const ResolvedScript = struct {
    allocator: Allocator,
    steps: []const formulas.ScriptStep,
    context: ScriptContext,
    allocations: std.ArrayListUnmanaged([]const u8),

    fn deinit(self: *ResolvedScript) void {
        for (self.allocations.items) |item| {
            self.allocator.free(item);
        }
        self.allocations.deinit(self.allocator);
        self.allocator.free(self.steps);
    }
};

const ScriptOutput = struct {
    id: []const u8,
    label: []const u8,
    methods: []const formulas.Method,
    script: ?formulas.Script,
    storage: ?formulas.StorageHints,
    method: ?formulas.Method,
    context: ?ScriptContext,
};

/// Allocator for FFI operations
/// Note: Zig's GeneralPurposeAllocator is internally thread-safe, so no external mutex is needed.
/// Each allocation/free operation is atomic with respect to other threads.
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

fn getAllocator() std.mem.Allocator {
    return gpa.allocator();
}

threadlocal var last_error_code: c_int = 0;
threadlocal var last_error_message: [256]u8 = undefined;
threadlocal var last_error_message_len: usize = 0;

fn clearLastError() void {
    last_error_code = 0;
    last_error_message_len = 0;
}

fn errorCodeFromAny(err: anyerror) c_int {
    return switch (err) {
        error.InvalidParameter => error_types.toErrorCode(error.InvalidParameter),
        error.StorageError => error_types.toErrorCode(error.StorageError),
        error.HttpError => error_types.toErrorCode(error.HttpError),
        error.AuthorizationDenied => error_types.toErrorCode(error.AuthorizationDenied),
        error.TokenExpired => error_types.toErrorCode(error.TokenExpired),
        error.NoRefreshToken => error_types.toErrorCode(error.NoRefreshToken),
        error.InvalidState => error_types.toErrorCode(error.InvalidState),
        error.DeviceCodeExpired => error_types.toErrorCode(error.DeviceCodeExpired),
        error.AuthorizationPending => error_types.toErrorCode(error.AuthorizationPending),
        error.SlowDown => error_types.toErrorCode(error.SlowDown),
        error.JsonError => error_types.toErrorCode(error.JsonError),
        error.IoError => error_types.toErrorCode(error.IoError),
        error.ServerError => error_types.toErrorCode(error.ServerError),
        error.CallbackServerError => error_types.toErrorCode(error.CallbackServerError),
        error.ConfigurationError => error_types.toErrorCode(error.ConfigurationError),
        error.LockError => error_types.toErrorCode(error.LockError),
        error.UnsupportedOperation => error_types.toErrorCode(error.UnsupportedOperation),
        error.OutOfMemory => error_types.toErrorCode(error.OutOfMemory),
        error.ConnectionFailed => error_types.toErrorCode(error.ConnectionFailed),
        error.Timeout => error_types.toErrorCode(error.Timeout),
        error.InsecureEndpoint => error_types.toErrorCode(error.ConfigurationError),
        error.InvalidSchema => error_types.toErrorCode(error.ConfigurationError),
        error.MissingEndpoint => error_types.toErrorCode(error.ConfigurationError),
        error.RegistrationFailed => error_types.toErrorCode(error.ServerError),
        else => 99, // SCHLUSSEL_ERROR_UNKNOWN
    };
}

fn setLastError(err: anyerror) void {
    last_error_code = errorCodeFromAny(err);
    const name = @errorName(err);
    last_error_message_len = @min(name.len, last_error_message.len - 1);
    @memcpy(last_error_message[0..last_error_message_len], name[0..last_error_message_len]);
}

fn setLastErrorMessage(code: c_int, message: []const u8) void {
    last_error_code = code;
    last_error_message_len = @min(message.len, last_error_message.len - 1);
    @memcpy(last_error_message[0..last_error_message_len], message[0..last_error_message_len]);
}

/// Get the last error code for the calling thread
export fn schlussel_last_error_code() c_int {
    return last_error_code;
}

/// Get the last error message for the calling thread
/// Caller must free the returned string with schlussel_string_free
export fn schlussel_last_error_message() ?[*:0]u8 {
    if (last_error_message_len == 0) return null;
    return dupeToC(last_error_message[0..last_error_message_len]);
}

/// Clear the last error for the calling thread
export fn schlussel_clear_last_error() void {
    clearLastError();
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
    clearLastError();
    if (client_id == null or app_name == null) {
        setLastError(error.InvalidParameter);
        return null;
    }
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
    clearLastError();
    if (client_id == null or app_name == null) {
        setLastError(error.InvalidParameter);
        return null;
    }
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
    clearLastError();
    if (client_id == null or authorization_endpoint == null or token_endpoint == null or redirect_uri == null) {
        setLastError(error.InvalidParameter);
        return null;
    }
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

    const storage_ptr = allocator.create(SecureStorage) catch |err| {
        setLastError(err);
        return null;
    };
    storage_ptr.* = storage;

    const client_ptr = allocator.create(OAuthClient) catch |err| {
        setLastError(err);
        allocator.destroy(storage_ptr);
        return null;
    };
    client_ptr.* = OAuthClient.init(allocator, config, storage_ptr.storage());

    const handle = allocator.create(SchlusselClient) catch |err| {
        setLastError(err);
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

    const storage = FileStorage.init(allocator, app_name) catch |err| {
        setLastError(err);
        return null;
    };

    const storage_ptr = allocator.create(FileStorage) catch |err| {
        setLastError(err);
        return null;
    };
    storage_ptr.* = storage;

    const client_ptr = allocator.create(OAuthClient) catch |err| {
        setLastError(err);
        allocator.destroy(storage_ptr);
        return null;
    };
    client_ptr.* = OAuthClient.init(allocator, config, storage_ptr.storage());

    const handle = allocator.create(SchlusselClient) catch |err| {
        setLastError(err);
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

    const storage_ptr = allocator.create(MemoryStorage) catch |err| {
        setLastError(err);
        return null;
    };
    storage_ptr.* = storage;

    const client_ptr = allocator.create(OAuthClient) catch |err| {
        setLastError(err);
        allocator.destroy(storage_ptr);
        return null;
    };
    client_ptr.* = OAuthClient.init(allocator, config, storage_ptr.storage());

    const handle = allocator.create(SchlusselClient) catch |err| {
        setLastError(err);
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
    clearLastError();
    const handle = client orelse {
        setLastError(error.InvalidParameter);
        return null;
    };
    const allocator = getAllocator();

    var token = handle.client.authorizeDevice() catch |err| {
        setLastError(err);
        return null;
    };

    const token_ptr = allocator.create(Token) catch |err| {
        setLastError(err);
        token.deinit();
        return null;
    };
    token_ptr.* = token;

    const token_handle = allocator.create(SchlusselToken) catch |err| {
        setLastError(err);
        token.deinit();
        allocator.destroy(token_ptr);
        return null;
    };
    token_handle.* = .{ .token = token_ptr };

    return token_handle;
}

/// Perform Authorization Code Flow with callback server
export fn schlussel_authorize(client: ?*SchlusselClient) ?*SchlusselToken {
    clearLastError();
    const handle = client orelse {
        setLastError(error.InvalidParameter);
        return null;
    };
    const allocator = getAllocator();

    var token = handle.client.authorize() catch |err| {
        setLastError(err);
        return null;
    };

    const token_ptr = allocator.create(Token) catch |err| {
        setLastError(err);
        token.deinit();
        return null;
    };
    token_ptr.* = token;

    const token_handle = allocator.create(SchlusselToken) catch |err| {
        setLastError(err);
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
    clearLastError();
    const handle = client orelse {
        setLastError(error.InvalidParameter);
        return errorCodeFromAny(error.InvalidParameter);
    };
    const token_handle = token orelse {
        setLastError(error.InvalidParameter);
        return errorCodeFromAny(error.InvalidParameter);
    };
    if (key == null) {
        setLastError(error.InvalidParameter);
        return errorCodeFromAny(error.InvalidParameter);
    }

    handle.client.saveToken(std.mem.span(key), token_handle.token.*) catch |err| {
        setLastError(err);
        return errorCodeFromAny(err);
    };

    return 0; // SCHLUSSEL_OK
}

/// Get a token from storage
export fn schlussel_get_token(
    client: ?*SchlusselClient,
    key: [*c]const u8,
) ?*SchlusselToken {
    clearLastError();
    const handle = client orelse {
        setLastError(error.InvalidParameter);
        return null;
    };
    if (key == null) {
        setLastError(error.InvalidParameter);
        return null;
    }
    const allocator = getAllocator();

    var token = (handle.client.getToken(std.mem.span(key)) catch |err| {
        setLastError(err);
        return null;
    }) orelse return null;

    const token_ptr = allocator.create(Token) catch |err| {
        setLastError(err);
        token.deinit();
        return null;
    };
    token_ptr.* = token;

    const token_handle = allocator.create(SchlusselToken) catch |err| {
        setLastError(err);
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
    clearLastError();
    const handle = client orelse {
        setLastError(error.InvalidParameter);
        return errorCodeFromAny(error.InvalidParameter);
    };
    if (key == null) {
        setLastError(error.InvalidParameter);
        return errorCodeFromAny(error.InvalidParameter);
    }

    handle.client.deleteToken(std.mem.span(key)) catch |err| {
        setLastError(err);
        return errorCodeFromAny(err);
    };

    return 0; // SCHLUSSEL_OK
}

/// Refresh an access token using a refresh token
export fn schlussel_refresh_token(
    client: ?*SchlusselClient,
    refresh_token: [*c]const u8,
) ?*SchlusselToken {
    clearLastError();
    const handle = client orelse {
        setLastError(error.InvalidParameter);
        return null;
    };
    if (refresh_token == null) {
        setLastError(error.InvalidParameter);
        return null;
    }
    const allocator = getAllocator();

    var token = handle.client.refreshToken(std.mem.span(refresh_token)) catch |err| {
        setLastError(err);
        return null;
    };

    const token_ptr = allocator.create(Token) catch |err| {
        setLastError(err);
        token.deinit();
        return null;
    };
    token_ptr.* = token;

    const token_handle = allocator.create(SchlusselToken) catch |err| {
        setLastError(err);
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
// Formula script operations
// ============================================================================

/// Emit a JSON script from a formula JSON document.
/// Caller must free the returned string with schlussel_string_free.
export fn schlussel_script_from_formula_json(formula_json: [*c]const u8) ?[*:0]u8 {
    clearLastError();
    if (formula_json == null) {
        setLastError(error.InvalidParameter);
        return null;
    }

    const allocator = getAllocator();
    var owned = formulas.loadFromJsonSlice(allocator, std.mem.span(formula_json)) catch |err| {
        setLastError(err);
        return null;
    };
    defer owned.deinit();

    const output = ScriptOutput{
        .id = owned.formula.id,
        .label = owned.formula.label,
        .methods = owned.formula.methods,
        .script = owned.formula.script,
        .storage = owned.formula.storage,
        .method = null,
        .context = null,
    };

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    std.json.Stringify.value(output, .{ .whitespace = .indent_2 }, &out.writer) catch |err| {
        setLastError(err);
        return null;
    };

    return dupeToC(out.written());
}

/// Emit a resolved JSON script from a formula JSON document.
/// Caller must free the returned string with schlussel_string_free.
export fn schlussel_script_resolve_from_formula_json(
    formula_json: [*c]const u8,
    method: [*c]const u8,
    client_id: [*c]const u8,
    client_secret: [*c]const u8,
    scope: [*c]const u8,
    redirect_uri: [*c]const u8,
) ?[*:0]u8 {
    clearLastError();
    if (formula_json == null or method == null) {
        setLastError(error.InvalidParameter);
        return null;
    }

    const allocator = getAllocator();
    var owned = formulas.loadFromJsonSlice(allocator, std.mem.span(formula_json)) catch |err| {
        setLastError(err);
        return null;
    };
    defer owned.deinit();

    const parsed_method = formulas.methodFromString(std.mem.span(method)) orelse {
        setLastError(error.InvalidParameter);
        return null;
    };

    var resolved = resolveScriptFromFormula(
        allocator,
        owned.asConst(),
        parsed_method,
        if (client_id != null) std.mem.span(client_id) else null,
        if (client_secret != null) std.mem.span(client_secret) else null,
        if (scope != null) std.mem.span(scope) else null,
        if (redirect_uri != null) std.mem.span(redirect_uri) else "http://127.0.0.1:0/callback",
    ) catch |err| {
        setLastError(err);
        return null;
    };
    defer resolved.deinit();

    const output = ScriptOutput{
        .id = owned.formula.id,
        .label = owned.formula.label,
        .methods = owned.formula.methods,
        .script = .{
            .register = if (owned.formula.script) |script| script.register else null,
            .steps = resolved.steps,
        },
        .storage = owned.formula.storage,
        .method = parsed_method,
        .context = resolved.context,
    };

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    std.json.Stringify.value(output, .{ .whitespace = .indent_2 }, &out.writer) catch |err| {
        setLastError(err);
        return null;
    };

    return dupeToC(out.written());
}

/// Execute a resolved script using an existing client.
export fn schlussel_run_script(client: ?*SchlusselClient, script_json: [*c]const u8) ?*SchlusselToken {
    clearLastError();
    const handle = client orelse {
        setLastError(error.InvalidParameter);
        return null;
    };
    if (script_json == null) {
        setLastError(error.InvalidParameter);
        return null;
    }
    const allocator = getAllocator();

    const parsed = std.json.parseFromSlice(ScriptOutput, allocator, std.mem.span(script_json), .{ .allocate = .alloc_always }) catch |err| {
        setLastError(err);
        return null;
    };
    defer parsed.deinit();

    const script = parsed.value.script orelse {
        setLastError(error.InvalidParameter);
        return null;
    };
    _ = script;
    const method = parsed.value.method orelse {
        setLastError(error.InvalidParameter);
        return null;
    };
    const context = parsed.value.context orelse {
        setLastError(error.InvalidParameter);
        return null;
    };

    var token: Token = undefined;

    switch (method) {
        .device_code => {
            const device_code = context.device_code orelse {
                setLastError(error.InvalidParameter);
                return null;
            };
            const interval = context.interval orelse 5;
            token = handle.client.pollDeviceCode(device_code, interval, context.expires_in) catch |err| {
                setLastError(err);
                return null;
            };
        },
        .authorization_code => {
            const authorize_url = context.authorize_url orelse {
                setLastError(error.InvalidParameter);
                return null;
            };
            const pkce_verifier = context.pkce_verifier orelse {
                setLastError(error.InvalidParameter);
                return null;
            };
            const state = context.state orelse {
                setLastError(error.InvalidParameter);
                return null;
            };
            const redirect = context.redirect_uri orelse {
                setLastError(error.InvalidParameter);
                return null;
            };

            const port = parseRedirectPort(redirect) catch |err| {
                setLastError(err);
                return null;
            };
            var server = callback.CallbackServer.init(allocator, port) catch |err| {
                setLastError(err);
                return null;
            };
            defer server.deinit();

            callback.openBrowser(authorize_url) catch {};

            var result = server.waitForCallback(120) catch |err| {
                setLastError(err);
                return null;
            };
            defer result.deinit();

            if (result.state) |callback_state| {
                if (!std.mem.eql(u8, callback_state, state)) {
                    setLastError(error.InvalidState);
                    return null;
                }
            }

            if (result.error_code != null) {
                setLastError(error.AuthorizationDenied);
                return null;
            }

            const code = result.code orelse {
                setLastError(error.ServerError);
                return null;
            };
            token = handle.client.exchangeCode(code, pkce_verifier, redirect) catch |err| {
                setLastError(err);
                return null;
            };
        },
        .api_key, .personal_access_token => {
            setLastError(error.UnsupportedOperation);
            return null;
        },
    }

    const token_ptr = allocator.create(Token) catch |err| {
        setLastError(err);
        token.deinit();
        return null;
    };
    token_ptr.* = token;

    const token_handle = allocator.create(SchlusselToken) catch |err| {
        setLastError(err);
        token.deinit();
        allocator.destroy(token_ptr);
        return null;
    };
    token_handle.* = .{ .token = token_ptr };

    return token_handle;
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

fn needsDynamicRedirectPort(redirect_uri: []const u8) bool {
    return std.mem.indexOf(u8, redirect_uri, ":0/") != null or std.mem.endsWith(u8, redirect_uri, ":0");
}

fn parseRedirectPort(redirect_uri: []const u8) !u16 {
    const scheme_idx = std.mem.indexOf(u8, redirect_uri, "://") orelse return error.InvalidParameter;
    const after_scheme = redirect_uri[(scheme_idx + 3)..];
    const path_idx = std.mem.indexOfScalar(u8, after_scheme, '/') orelse after_scheme.len;
    const host_port = after_scheme[0..path_idx];

    if (host_port.len == 0) return error.InvalidParameter;

    if (host_port[0] == '[') {
        const end_bracket = std.mem.indexOfScalar(u8, host_port, ']') orelse return error.InvalidParameter;
        if (end_bracket + 1 >= host_port.len or host_port[end_bracket + 1] != ':') {
            return error.InvalidParameter;
        }
        const port_str = host_port[(end_bracket + 2)..];
        return std.fmt.parseInt(u16, port_str, 10);
    }

    const colon_idx = std.mem.indexOfScalar(u8, host_port, ':') orelse return error.InvalidParameter;
    const port_str = host_port[(colon_idx + 1)..];
    if (port_str.len == 0) return error.InvalidParameter;
    return std.fmt.parseInt(u16, port_str, 10);
}

const Replacement = struct {
    key: []const u8,
    value: []const u8,
};

fn expandTemplate(
    allocator: Allocator,
    input: []const u8,
    replacements: []const Replacement,
) ![]const u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '{') {
            const end = std.mem.indexOfScalarPos(u8, input, i + 1, '}');
            if (end) |pos| {
                const key = input[(i + 1)..pos];
                var replaced = false;
                for (replacements) |replacement| {
                    if (std.mem.eql(u8, replacement.key, key)) {
                        try buf.appendSlice(allocator, replacement.value);
                        replaced = true;
                        break;
                    }
                }
                if (!replaced) {
                    try buf.appendSlice(allocator, input[i .. pos + 1]);
                }
                i = pos + 1;
                continue;
            }
        }
        try buf.append(allocator, input[i]);
        i += 1;
    }

    return buf.toOwnedSlice(allocator);
}

fn expandScriptSteps(
    allocator: Allocator,
    steps: []const formulas.ScriptStep,
    replacements: []const Replacement,
    context: ScriptContext,
    allocations: *std.ArrayListUnmanaged([]const u8),
) !ResolvedScript {
    const steps_out = try allocator.alloc(formulas.ScriptStep, steps.len);
    errdefer allocator.free(steps_out);

    for (steps, 0..) |step, idx| {
        var value_out: ?[]const u8 = null;
        if (step.value) |value| {
            const expanded = try expandTemplate(allocator, value, replacements);
            try allocations.append(allocator, expanded);
            value_out = expanded;
        }

        var note_out: ?[]const u8 = null;
        if (step.note) |note| {
            const expanded = try expandTemplate(allocator, note, replacements);
            try allocations.append(allocator, expanded);
            note_out = expanded;
        }

        steps_out[idx] = .{
            .@"type" = step.@"type",
            .value = value_out,
            .note = note_out,
        };
    }

    return .{
        .allocator = allocator,
        .steps = steps_out,
        .context = context,
        .allocations = allocations.*,
    };
}

fn resolveScriptFromFormula(
    allocator: Allocator,
    formula: *const formulas.Formula,
    method: formulas.Method,
    client_id_override: ?[]const u8,
    client_secret_override: ?[]const u8,
    scope_override: ?[]const u8,
    redirect_uri: []const u8,
) !ResolvedScript {
    const default_device_steps = [_]formulas.ScriptStep{
        .{ .@"type" = "open_url", .value = "{verification_uri}", .note = null },
        .{ .@"type" = "enter_code", .value = "{user_code}", .note = null },
        .{ .@"type" = "wait_for_token", .value = null, .note = null },
    };
    const default_code_steps = [_]formulas.ScriptStep{
        .{ .@"type" = "open_url", .value = "{authorize_url}", .note = null },
        .{ .@"type" = "wait_for_callback", .value = null, .note = null },
    };
    const default_api_key_steps = [_]formulas.ScriptStep{
        .{ .@"type" = "copy_key", .value = null, .note = "Paste your API key into the agent." },
    };

    const steps_source = if (formula.script) |script|
        script.steps orelse switch (method) {
            .device_code => default_device_steps[0..],
            .authorization_code => default_code_steps[0..],
            .api_key, .personal_access_token => default_api_key_steps[0..],
        }
    else switch (method) {
        .device_code => default_device_steps[0..],
        .authorization_code => default_code_steps[0..],
        .api_key, .personal_access_token => default_api_key_steps[0..],
    };

    var replacements: std.ArrayListUnmanaged(Replacement) = .{};
    defer replacements.deinit(allocator);

    var allocations: std.ArrayListUnmanaged([]const u8) = .{};
    errdefer {
        for (allocations.items) |item| allocator.free(item);
        allocations.deinit(allocator);
    }

    var context = ScriptContext{};

    switch (method) {
        .authorization_code => {
            var resolved_redirect_uri = redirect_uri;
            if (needsDynamicRedirectPort(redirect_uri)) {
                var server = try callback.CallbackServer.init(allocator, 0);
                defer server.deinit();
                resolved_redirect_uri = try server.getCallbackUrl(allocator);
                try allocations.append(allocator, resolved_redirect_uri);
            } else {
                const redirect_dup = try allocator.dupe(u8, redirect_uri);
                try allocations.append(allocator, redirect_dup);
                resolved_redirect_uri = redirect_dup;
            }

            var config = try oauth.configFromFormula(
                allocator,
                formula,
                client_id_override,
                client_secret_override,
                resolved_redirect_uri,
                scope_override,
            );
            defer config.deinit();

            const pair = pkce.Pkce.generate();
            const verifier = try allocator.dupe(u8, pair.getVerifier());
            try allocations.append(allocator, verifier);
            try replacements.append(allocator, .{ .key = "pkce_verifier", .value = verifier });

            var state_bytes: [16]u8 = undefined;
            std.crypto.random.bytes(&state_bytes);
            var state: [22]u8 = undefined;
            _ = std.base64.url_safe_no_pad.Encoder.encode(&state, &state_bytes);
            const state_dup = try allocator.dupe(u8, &state);
            try allocations.append(allocator, state_dup);
            try replacements.append(allocator, .{ .key = "state", .value = state_dup });

            const authorize_url = try callback.buildAuthorizationUrl(
                allocator,
                config.authorization_endpoint,
                config.client_id,
                resolved_redirect_uri,
                config.scope,
                &state,
                pair.getChallenge(),
            );
            const authorize_dup = try allocator.dupe(u8, authorize_url);
            allocator.free(authorize_url);
            try allocations.append(allocator, authorize_dup);
            try replacements.append(allocator, .{ .key = "authorize_url", .value = authorize_dup });

            context.authorize_url = authorize_dup;
            context.pkce_verifier = verifier;
            context.state = state_dup;
            context.redirect_uri = resolved_redirect_uri;
        },
        .device_code => {
            var config = try oauth.configFromFormula(
                allocator,
                formula,
                client_id_override,
                client_secret_override,
                redirect_uri,
                scope_override,
            );
            defer config.deinit();

            var storage = session.MemoryStorage.init(allocator);
            defer storage.deinit();

            var client = oauth.OAuthClient.init(allocator, config.toConfig(), storage.storage());
            defer client.deinit();

            var device_response = try client.requestDeviceCode();
            defer device_response.deinit();

            const verification_uri = try allocator.dupe(u8, device_response.verification_uri);
            try allocations.append(allocator, verification_uri);
            try replacements.append(allocator, .{ .key = "verification_uri", .value = verification_uri });
            context.verification_uri = verification_uri;

            if (device_response.verification_uri_complete) |uri| {
                const complete_dup = try allocator.dupe(u8, uri);
                try allocations.append(allocator, complete_dup);
                try replacements.append(allocator, .{ .key = "verification_uri_complete", .value = complete_dup });
                context.verification_uri_complete = complete_dup;
            }

            const user_code = try allocator.dupe(u8, device_response.user_code);
            try allocations.append(allocator, user_code);
            try replacements.append(allocator, .{ .key = "user_code", .value = user_code });
            context.user_code = user_code;

            const device_code = try allocator.dupe(u8, device_response.device_code);
            try allocations.append(allocator, device_code);
            try replacements.append(allocator, .{ .key = "device_code", .value = device_code });
            context.device_code = device_code;
            context.interval = device_response.interval;
            context.expires_in = device_response.expires_in;
        },
        .api_key, .personal_access_token => {},
    }

    return expandScriptSteps(allocator, steps_source, replacements.items, context, &allocations);
}

fn freeStringSlice(allocator: Allocator, slice: []const []const u8) void {
    for (slice) |item| {
        allocator.free(item);
    }
    allocator.free(slice);
}

const RegistrationMetadata = struct {
    metadata: ClientMetadata,
    redirect_uris_list: std.ArrayList([]const u8),
    grant_types: ?[]const []const u8 = null,
    response_types: ?[]const []const u8 = null,

    fn init(
        allocator: Allocator,
        redirect_uris: [*c]const [*c]const u8,
        redirect_uris_count: usize,
        client_name: [*c]const u8,
        grant_types: [*c]const u8,
        response_types: [*c]const u8,
        scope: [*c]const u8,
        token_auth_method: [*c]const u8,
    ) !RegistrationMetadata {
        var metadata = try ClientMetadata.init(allocator);
        errdefer metadata.deinit();

        const uris_ptr: [*]const [*:0]const u8 = @ptrCast(redirect_uris);
        const uris_slice = uris_ptr[0..redirect_uris_count];
        var redirect_uris_list: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (redirect_uris_list.items) |uri| allocator.free(uri);
            redirect_uris_list.deinit(allocator);
        }

        for (uris_slice) |uri_c_str| {
            const uri_dup = try allocator.dupe(u8, std.mem.span(uri_c_str));
            try redirect_uris_list.append(allocator, uri_dup);
        }
        metadata.redirect_uris = redirect_uris_list.items;

        if (client_name != null) {
            metadata.client_name = std.mem.span(client_name);
        }

        if (grant_types != null) {
            metadata.grant_types = try parseCommaSeparated(allocator, std.mem.span(grant_types));
        }

        if (response_types != null) {
            metadata.response_types = try parseCommaSeparated(allocator, std.mem.span(response_types));
        }

        if (scope != null) {
            metadata.scope = std.mem.span(scope);
        }

        if (token_auth_method != null) {
            metadata.token_endpoint_auth_method = std.mem.span(token_auth_method);
        }

        return .{
            .metadata = metadata,
            .redirect_uris_list = redirect_uris_list,
            .grant_types = metadata.grant_types,
            .response_types = metadata.response_types,
        };
    }

    fn deinit(self: *RegistrationMetadata, allocator: Allocator) void {
        self.metadata.deinit();
        for (self.redirect_uris_list.items) |uri| allocator.free(uri);
        self.redirect_uris_list.deinit(allocator);
        if (self.grant_types) |slice| {
            freeStringSlice(allocator, slice);
        }
        if (self.response_types) |slice| {
            freeStringSlice(allocator, slice);
        }
    }
};

// ============================================================================
// Dynamic Client Registration functions
// ============================================================================

/// Create a new dynamic registration client
export fn schlussel_registration_new(endpoint: [*c]const u8) ?*SchlusselRegistrationClient {
    const allocator = getAllocator();
    clearLastError();
    if (endpoint == null) {
        setLastError(error.InvalidParameter);
        return null;
    }

    var client = DynamicRegistration.init(allocator, std.mem.span(endpoint)) catch |err| {
        setLastError(err);
        return null;
    };

    const client_ptr = allocator.create(DynamicRegistration) catch |err| {
        setLastError(err);
        client.deinit();
        return null;
    };
    client_ptr.* = client;

    const handle = allocator.create(SchlusselRegistrationClient) catch |err| {
        setLastError(err);
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
    clearLastError();
    const handle = reg_client orelse {
        setLastError(error.InvalidParameter);
        return null;
    };
    if (redirect_uris == null or redirect_uris_count == 0) {
        setLastError(error.InvalidParameter);
        return null;
    }
    const allocator = getAllocator();

    var metadata = RegistrationMetadata.init(
        allocator,
        redirect_uris,
        redirect_uris_count,
        client_name,
        grant_types,
        response_types,
        scope,
        token_auth_method,
    ) catch |err| {
        setLastError(err);
        return null;
    };
    defer metadata.deinit(allocator);

    // Register the client
    var response = handle.client.register(metadata.metadata) catch |err| {
        setLastError(err);
        return null;
    };

    const response_ptr = allocator.create(ClientRegistrationResponse) catch |err| {
        setLastError(err);
        response.deinit();
        return null;
    };
    response_ptr.* = response;

    const response_handle = allocator.create(SchlusselRegistrationResponse) catch |err| {
        setLastError(err);
        response.deinit();
        allocator.destroy(response_ptr);
        return null;
    };
    response_handle.* = .{ .response = response_ptr };

    return response_handle;
}

/// Read client configuration from the registration endpoint
///
/// Returns: Registration response handle on success, NULL on error
export fn schlussel_registration_read(
    reg_client: ?*SchlusselRegistrationClient,
    registration_access_token: [*c]const u8,
) ?*SchlusselRegistrationResponse {
    clearLastError();
    const handle = reg_client orelse {
        setLastError(error.InvalidParameter);
        return null;
    };
    if (registration_access_token == null) {
        setLastError(error.InvalidParameter);
        return null;
    }
    const allocator = getAllocator();

    var response = handle.client.read(std.mem.span(registration_access_token)) catch |err| {
        setLastError(err);
        return null;
    };

    const response_ptr = allocator.create(ClientRegistrationResponse) catch |err| {
        setLastError(err);
        response.deinit();
        return null;
    };
    response_ptr.* = response;

    const response_handle = allocator.create(SchlusselRegistrationResponse) catch |err| {
        setLastError(err);
        response.deinit();
        allocator.destroy(response_ptr);
        return null;
    };
    response_handle.* = .{ .response = response_ptr };

    return response_handle;
}

/// Update client configuration at the authorization server
///
/// Returns: Registration response handle on success, NULL on error
export fn schlussel_registration_update(
    reg_client: ?*SchlusselRegistrationClient,
    registration_access_token: [*c]const u8,
    redirect_uris: [*c]const [*c]const u8,
    redirect_uris_count: usize,
    client_name: [*c]const u8,
    grant_types: [*c]const u8,
    response_types: [*c]const u8,
    scope: [*c]const u8,
    token_auth_method: [*c]const u8,
) ?*SchlusselRegistrationResponse {
    clearLastError();
    const handle = reg_client orelse {
        setLastError(error.InvalidParameter);
        return null;
    };
    if (registration_access_token == null) {
        setLastError(error.InvalidParameter);
        return null;
    }
    if (redirect_uris == null and redirect_uris_count > 0) {
        setLastError(error.InvalidParameter);
        return null;
    }
    const allocator = getAllocator();

    var metadata = RegistrationMetadata.init(
        allocator,
        redirect_uris,
        redirect_uris_count,
        client_name,
        grant_types,
        response_types,
        scope,
        token_auth_method,
    ) catch |err| {
        setLastError(err);
        return null;
    };
    defer metadata.deinit(allocator);

    var response = handle.client.update(std.mem.span(registration_access_token), metadata.metadata) catch |err| {
        setLastError(err);
        return null;
    };

    const response_ptr = allocator.create(ClientRegistrationResponse) catch |err| {
        setLastError(err);
        response.deinit();
        return null;
    };
    response_ptr.* = response;

    const response_handle = allocator.create(SchlusselRegistrationResponse) catch |err| {
        setLastError(err);
        response.deinit();
        allocator.destroy(response_ptr);
        return null;
    };
    response_handle.* = .{ .response = response_ptr };

    return response_handle;
}

/// Delete client registration
///
/// Returns: 0 on success, -1 on error
export fn schlussel_registration_delete(
    reg_client: ?*SchlusselRegistrationClient,
    registration_access_token: [*c]const u8,
) c_int {
    clearLastError();
    const handle = reg_client orelse {
        setLastError(error.InvalidParameter);
        return errorCodeFromAny(error.InvalidParameter);
    };
    if (registration_access_token == null) {
        setLastError(error.InvalidParameter);
        return errorCodeFromAny(error.InvalidParameter);
    }
    handle.client.delete(std.mem.span(registration_access_token)) catch |err| {
        setLastError(err);
        return errorCodeFromAny(err);
    };
    return 0;
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

test "FFI last error reports invalid parameters" {
    schlussel_clear_last_error();

    const client = schlussel_registration_new(null);
    try std.testing.expect(client == null);
    try std.testing.expectEqual(
        @as(c_int, error_types.toErrorCode(error.InvalidParameter)),
        schlussel_last_error_code(),
    );

    const msg = schlussel_last_error_message();
    try std.testing.expect(msg != null);
    if (msg) |m| {
        schlussel_string_free(m);
    }
}

test "FFI last error clears" {
    schlussel_clear_last_error();
    try std.testing.expectEqual(@as(c_int, 0), schlussel_last_error_code());
    try std.testing.expect(schlussel_last_error_message() == null);
}
