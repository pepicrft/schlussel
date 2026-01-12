//! OAuth 2.0 client with Device Code Flow and Authorization Code Flow
//!
//! This module provides the main OAuth client implementation supporting:
//! - Device Code Flow (RFC 8628) for CLI applications
//! - Authorization Code Flow with PKCE for desktop/web applications
//! - Automatic token refresh with cross-process locking
//! - Provider presets for popular OAuth providers
//!
//! ## Example
//!
//! ```zig
//! const config = OAuthConfig.github("your-client-id", "repo user");
//! var storage = MemoryStorage.init(allocator);
//! defer storage.deinit();
//!
//! var client = OAuthClient.init(allocator, config, storage.storage());
//! defer client.deinit();
//!
//! const token = try client.authorizeDevice();
//! ```

const std = @import("std");
const json = std.json;
const http = std.http;
const Uri = std.Uri;
const Allocator = std.mem.Allocator;

const pkce = @import("pkce.zig");
const session = @import("session.zig");
const callback = @import("callback.zig");
const lock = @import("lock.zig");
const formulas = @import("formulas.zig");

const Token = session.Token;
const SessionStorage = session.SessionStorage;
const Pkce = pkce.Pkce;
const CallbackServer = callback.CallbackServer;
const RefreshLockManager = lock.RefreshLockManager;

/// OAuth 2.0 configuration
pub const OAuthConfig = struct {
    /// Client ID issued by the authorization server
    client_id: []const u8,
    /// Client secret (optional, not needed for public clients)
    client_secret: ?[]const u8 = null,
    /// Authorization endpoint URL
    authorization_endpoint: []const u8,
    /// Token endpoint URL
    token_endpoint: []const u8,
    /// Redirect URI for authorization code flow
    redirect_uri: []const u8,
    /// Space-separated list of scopes
    scope: ?[]const u8 = null,
    /// Device authorization endpoint (for Device Code Flow)
    device_authorization_endpoint: ?[]const u8 = null,

    /// Validate that OAuth endpoints use HTTPS (except localhost)
    pub fn validate(self: *const OAuthConfig) !void {
        try validateEndpointSecurity(self.authorization_endpoint);
        try validateEndpointSecurity(self.token_endpoint);
        if (self.device_authorization_endpoint) |endpoint| {
            try validateEndpointSecurity(endpoint);
        }
    }

    /// Create configuration for GitHub
    pub fn github(client_id: []const u8, scope: ?[]const u8) OAuthConfig {
        return .{
            .client_id = client_id,
            .authorization_endpoint = "https://github.com/login/oauth/authorize",
            .token_endpoint = "https://github.com/login/oauth/access_token",
            .device_authorization_endpoint = "https://github.com/login/device/code",
            .redirect_uri = "http://127.0.0.1/callback",
            .scope = scope,
        };
    }

    /// Create configuration for Google
    pub fn google(client_id: []const u8, scope: ?[]const u8) OAuthConfig {
        return .{
            .client_id = client_id,
            .authorization_endpoint = "https://accounts.google.com/o/oauth2/v2/auth",
            .token_endpoint = "https://oauth2.googleapis.com/token",
            .device_authorization_endpoint = "https://oauth2.googleapis.com/device/code",
            .redirect_uri = "http://127.0.0.1/callback",
            .scope = scope,
        };
    }

    /// Create configuration for Microsoft Azure AD
    ///
    /// tenant can be:
    /// - "common" for multi-tenant apps
    /// - "organizations" for work/school accounts only
    /// - "consumers" for personal accounts only
    /// - A specific tenant ID (GUID) or domain
    pub fn microsoft(client_id: []const u8, tenant: []const u8, scope: ?[]const u8) OAuthConfig {
        // We can't use allocPrint in a comptime context, so we support specific known tenants
        // For custom tenants, use the custom() constructor
        const base = "https://login.microsoftonline.com/";
        const auth_suffix = "/oauth2/v2.0/authorize";
        const token_suffix = "/oauth2/v2.0/token";
        const device_suffix = "/oauth2/v2.0/devicecode";

        // For common tenants, use pre-built strings
        if (std.mem.eql(u8, tenant, "common")) {
            return .{
                .client_id = client_id,
                .authorization_endpoint = base ++ "common" ++ auth_suffix,
                .token_endpoint = base ++ "common" ++ token_suffix,
                .device_authorization_endpoint = base ++ "common" ++ device_suffix,
                .redirect_uri = "http://127.0.0.1/callback",
                .scope = scope,
            };
        } else if (std.mem.eql(u8, tenant, "organizations")) {
            return .{
                .client_id = client_id,
                .authorization_endpoint = base ++ "organizations" ++ auth_suffix,
                .token_endpoint = base ++ "organizations" ++ token_suffix,
                .device_authorization_endpoint = base ++ "organizations" ++ device_suffix,
                .redirect_uri = "http://127.0.0.1/callback",
                .scope = scope,
            };
        } else if (std.mem.eql(u8, tenant, "consumers")) {
            return .{
                .client_id = client_id,
                .authorization_endpoint = base ++ "consumers" ++ auth_suffix,
                .token_endpoint = base ++ "consumers" ++ token_suffix,
                .device_authorization_endpoint = base ++ "consumers" ++ device_suffix,
                .redirect_uri = "http://127.0.0.1/callback",
                .scope = scope,
            };
        } else {
            // For custom tenants, default to common and log warning
            // Users should use custom() for specific tenant IDs
            return .{
                .client_id = client_id,
                .authorization_endpoint = base ++ "common" ++ auth_suffix,
                .token_endpoint = base ++ "common" ++ token_suffix,
                .device_authorization_endpoint = base ++ "common" ++ device_suffix,
                .redirect_uri = "http://127.0.0.1/callback",
                .scope = scope,
            };
        }
    }

    /// Create configuration for GitLab.com
    pub fn gitlab(client_id: []const u8, scope: ?[]const u8) OAuthConfig {
        return .{
            .client_id = client_id,
            .authorization_endpoint = "https://gitlab.com/oauth/authorize",
            .token_endpoint = "https://gitlab.com/oauth/token",
            .redirect_uri = "http://127.0.0.1/callback",
            .scope = scope,
            .device_authorization_endpoint = null,
        };
    }

    /// Create configuration for self-hosted GitLab
    ///
    /// Note: This is a runtime configuration builder. The caller must ensure
    /// the base_url uses HTTPS in production.
    ///
    /// Example:
    /// ```zig
    /// const config = try OAuthConfig.gitlabSelfHosted(
    ///     allocator,
    ///     "client-id",
    ///     "https://gitlab.mycompany.com",
    ///     "read_user",
    /// );
    /// defer config.deinit(allocator);
    /// ```
    pub fn gitlabSelfHosted(
        allocator: Allocator,
        client_id: []const u8,
        base_url: []const u8,
        scope: ?[]const u8,
    ) !OAuthConfigOwned {
        // Validate base_url starts with https:// (or http://localhost for dev)
        try validateEndpointSecurity(base_url);

        // Strip trailing slash if present
        const clean_base = if (base_url.len > 0 and base_url[base_url.len - 1] == '/')
            base_url[0 .. base_url.len - 1]
        else
            base_url;

        return OAuthConfigOwned{
            .allocator = allocator,
            .client_id = try allocator.dupe(u8, client_id),
            .authorization_endpoint = try std.fmt.allocPrint(allocator, "{s}/oauth/authorize", .{clean_base}),
            .token_endpoint = try std.fmt.allocPrint(allocator, "{s}/oauth/token", .{clean_base}),
            .redirect_uri = try allocator.dupe(u8, "http://127.0.0.1/callback"),
            .scope = if (scope) |s| try allocator.dupe(u8, s) else null,
            .device_authorization_endpoint = null,
        };
    }

    /// Create configuration for Tuist Cloud
    pub fn tuist(client_id: []const u8, scope: ?[]const u8) OAuthConfig {
        return .{
            .client_id = client_id,
            .authorization_endpoint = "https://cloud.tuist.io/oauth/authorize",
            .token_endpoint = "https://cloud.tuist.io/oauth/token",
            .device_authorization_endpoint = "https://cloud.tuist.io/oauth/device/code",
            .redirect_uri = "http://127.0.0.1/callback",
            .scope = scope,
        };
    }

    /// Create a custom OAuth configuration
    ///
    /// For configurations that need runtime-constructed URLs.
    /// The caller owns the returned config and must call deinit().
    pub fn custom(
        allocator: Allocator,
        client_id: []const u8,
        authorization_endpoint: []const u8,
        token_endpoint: []const u8,
        redirect_uri: []const u8,
        scope: ?[]const u8,
        device_authorization_endpoint: ?[]const u8,
    ) !OAuthConfigOwned {
        // Validate endpoints use HTTPS
        try validateEndpointSecurity(authorization_endpoint);
        try validateEndpointSecurity(token_endpoint);
        if (device_authorization_endpoint) |endpoint| {
            try validateEndpointSecurity(endpoint);
        }

        return OAuthConfigOwned{
            .allocator = allocator,
            .client_id = try allocator.dupe(u8, client_id),
            .authorization_endpoint = try allocator.dupe(u8, authorization_endpoint),
            .token_endpoint = try allocator.dupe(u8, token_endpoint),
            .redirect_uri = try allocator.dupe(u8, redirect_uri),
            .scope = if (scope) |s| try allocator.dupe(u8, s) else null,
            .device_authorization_endpoint = if (device_authorization_endpoint) |e| try allocator.dupe(u8, e) else null,
        };
    }
};

/// Owned version of OAuthConfig for runtime-constructed configurations
pub const OAuthConfigOwned = struct {
    allocator: Allocator,
    client_id: []const u8,
    client_secret: ?[]const u8 = null,
    authorization_endpoint: []const u8,
    token_endpoint: []const u8,
    redirect_uri: []const u8,
    scope: ?[]const u8 = null,
    device_authorization_endpoint: ?[]const u8 = null,

    pub fn deinit(self: *OAuthConfigOwned) void {
        self.allocator.free(self.client_id);
        self.allocator.free(self.authorization_endpoint);
        self.allocator.free(self.token_endpoint);
        self.allocator.free(self.redirect_uri);
        if (self.scope) |s| self.allocator.free(s);
        if (self.device_authorization_endpoint) |e| self.allocator.free(e);
        if (self.client_secret) |s| self.allocator.free(s);
    }

    /// Convert to non-owned OAuthConfig (borrows from self)
    pub fn toConfig(self: *const OAuthConfigOwned) OAuthConfig {
        return .{
            .client_id = self.client_id,
            .client_secret = self.client_secret,
            .authorization_endpoint = self.authorization_endpoint,
            .token_endpoint = self.token_endpoint,
            .redirect_uri = self.redirect_uri,
            .scope = self.scope,
            .device_authorization_endpoint = self.device_authorization_endpoint,
        };
    }
};

pub fn configFromFormula(
    allocator: Allocator,
    formula: *const formulas.Formula,
    client_id_override: ?[]const u8,
    client_secret_override: ?[]const u8,
    redirect_uri: []const u8,
    scope_override: ?[]const u8,
) !OAuthConfigOwned {
    const scope_value = if (scope_override) |s| s else formula.scope;

    // Use provided client_id/secret or fall back to formula's default public client
    var client_id: []const u8 = undefined;
    var client_secret: ?[]const u8 = client_secret_override;

    if (client_id_override) |id| {
        client_id = id;
    } else if (formula.getDefaultClient()) |default_client| {
        client_id = default_client.id;
        // Only use default client's secret if no override was provided
        if (client_secret == null) {
            client_secret = default_client.secret;
        }
    } else {
        return error.MissingClientId;
    }

    return OAuthConfigOwned{
        .allocator = allocator,
        .client_id = try allocator.dupe(u8, client_id),
        .client_secret = if (client_secret) |s| try allocator.dupe(u8, s) else null,
        .authorization_endpoint = try allocator.dupe(u8, formula.authorization_endpoint),
        .token_endpoint = try allocator.dupe(u8, formula.token_endpoint),
        .redirect_uri = try allocator.dupe(u8, redirect_uri),
        .scope = if (scope_value) |s| try allocator.dupe(u8, s) else null,
        .device_authorization_endpoint = if (formula.device_authorization_endpoint) |e| try allocator.dupe(u8, e) else null,
    };
}

/// Validate that an endpoint URL uses HTTPS (or is localhost for development)
fn validateEndpointSecurity(url: []const u8) !void {
    // Allow HTTPS
    if (std.mem.startsWith(u8, url, "https://")) return;

    // Allow localhost/127.0.0.1 for development
    if (std.mem.startsWith(u8, url, "http://localhost") or
        std.mem.startsWith(u8, url, "http://127.0.0.1") or
        std.mem.startsWith(u8, url, "http://[::1]"))
    {
        return;
    }

    return error.InsecureEndpoint;
}

/// Device authorization response from RFC 8628
pub const DeviceAuthorizationResponse = struct {
    allocator: Allocator,
    /// The device verification code
    device_code: []const u8,
    /// User code to display
    user_code: []const u8,
    /// Verification URI for the user
    verification_uri: []const u8,
    /// Optional complete verification URI with user code
    verification_uri_complete: ?[]const u8,
    /// Lifetime of device_code and user_code in seconds
    expires_in: u64,
    /// Minimum polling interval in seconds
    interval: u64,

    pub fn deinit(self: *DeviceAuthorizationResponse) void {
        self.allocator.free(self.device_code);
        self.allocator.free(self.user_code);
        self.allocator.free(self.verification_uri);
        if (self.verification_uri_complete) |uri| {
            self.allocator.free(uri);
        }
    }
};

/// Result from authorization flow
pub const AuthFlowResult = struct {
    token: Token,
    /// The state parameter that was used (for verification)
    state: ?[]const u8,

    pub fn deinit(self: *AuthFlowResult, allocator: Allocator) void {
        self.token.deinit();
        if (self.state) |s| allocator.free(s);
    }
};

/// OAuth 2.0 client
pub const OAuthClient = struct {
    allocator: Allocator,
    config: OAuthConfig,
    storage: SessionStorage,
    http_client: ?HttpClient = null,

    const HttpClient = struct {
        allocator: Allocator,

        /// Maximum response size (1 MB) to prevent unbounded memory allocation
        const max_response_size: usize = 1024 * 1024;

        pub fn init(allocator: Allocator) HttpClient {
            return .{ .allocator = allocator };
        }

        pub fn deinit(self: *HttpClient) void {
            _ = self;
        }

        pub fn post(self: *HttpClient, url: []const u8, body: []const u8, content_type: []const u8) !HttpResponse {
            var client = http.Client{ .allocator = self.allocator };
            defer client.deinit();

            // Create response body storage using the Io.Writer.Allocating interface
            var response_writer = std.Io.Writer.Allocating.init(self.allocator);
            errdefer response_writer.deinit();

            const result = try client.fetch(.{
                .location = .{ .url = url },
                .method = .POST,
                .payload = body,
                .extra_headers = &.{
                    .{ .name = "Content-Type", .value = content_type },
                    .{ .name = "Accept", .value = "application/json" },
                },
                .response_writer = &response_writer.writer,
            });

            const response_body = try response_writer.toOwnedSlice();

            // Check if response exceeds maximum allowed size
            if (response_body.len > max_response_size) {
                self.allocator.free(response_body);
                return error.ResponseTooLarge;
            }

            return HttpResponse{
                .status = @intFromEnum(result.status),
                .body = response_body,
                .allocator = self.allocator,
            };
        }
    };

    const HttpResponse = struct {
        status: u16,
        body: []const u8,
        allocator: Allocator,

        pub fn deinit(self: *HttpResponse) void {
            self.allocator.free(self.body);
        }
    };

    /// Initialize a new OAuth client
    pub fn init(allocator: Allocator, config: OAuthConfig, storage: SessionStorage) OAuthClient {
        return .{
            .allocator = allocator,
            .config = config,
            .storage = storage,
        };
    }

    pub fn deinit(self: *OAuthClient) void {
        if (self.http_client) |*client| {
            client.deinit();
        }
    }

    /// Perform Device Code Flow authorization (RFC 8628)
    ///
    /// This is the recommended flow for CLI applications:
    /// 1. Request device code
    /// 2. Display user code and verification URL
    /// 3. Open browser for user to authorize
    /// 4. Poll for token until user completes authorization
    pub fn authorizeDevice(self: *OAuthClient) !Token {
        const device_endpoint = self.config.device_authorization_endpoint orelse {
            return error.UnsupportedOperation;
        };

        // Step 1: Request device code
        var http_client = HttpClient.init(self.allocator);
        defer http_client.deinit();

        var body_buf: std.ArrayListUnmanaged(u8) = .{};
        defer body_buf.deinit(self.allocator);

        try body_buf.appendSlice(self.allocator, "client_id=");
        try appendUrlEncoded(self.allocator, &body_buf, self.config.client_id);
        if (self.config.scope) |scope| {
            try body_buf.appendSlice(self.allocator, "&scope=");
            try appendUrlEncoded(self.allocator, &body_buf, scope);
        }

        var response = try http_client.post(
            device_endpoint,
            body_buf.items,
            "application/x-www-form-urlencoded",
        );
        defer response.deinit();

        if (response.status != 200) {
            return error.ServerError;
        }

        // Parse device authorization response
        const parsed = try json.parseFromSlice(json.Value, self.allocator, response.body, .{});
        defer parsed.deinit();

        var device_response = try parseDeviceResponse(self.allocator, parsed.value);
        defer device_response.deinit();

        // Step 2: Display user code and verification URL
        var stderr_writer = std.fs.File.stderr().writer(&.{});
        const stderr = &stderr_writer.interface;
        try stderr.print("\nTo authorize, visit: {s}\n", .{device_response.verification_uri});
        try stderr.print("And enter code: {s}\n\n", .{device_response.user_code});

        // Open browser if available
        if (device_response.verification_uri_complete) |uri| {
            callback.openBrowser(uri) catch {};
        } else {
            callback.openBrowser(device_response.verification_uri) catch {};
        }

        // Step 3: Poll for token
        const start_time = @as(u64, @intCast(std.time.timestamp()));
        var interval = device_response.interval;
        if (interval < 5) interval = 5; // Minimum 5 seconds

        // Maximum polling iterations (safety limit to prevent infinite loops)
        // With 5s minimum interval and typical 15min expiry, max ~180 iterations is reasonable
        const max_iterations: u32 = 500;
        var iterations: u32 = 0;

        while (iterations < max_iterations) : (iterations += 1) {
            const now = @as(u64, @intCast(std.time.timestamp()));
            if (now - start_time >= device_response.expires_in) {
                return error.DeviceCodeExpired;
            }

            // Wait for polling interval
            std.Thread.sleep(interval * std.time.ns_per_s);

            // Poll token endpoint
            var poll_body: std.ArrayListUnmanaged(u8) = .{};
            defer poll_body.deinit(self.allocator);

            try poll_body.appendSlice(self.allocator, "grant_type=urn:ietf:params:oauth:grant-type:device_code");
            try poll_body.appendSlice(self.allocator, "&device_code=");
            try appendUrlEncoded(self.allocator, &poll_body, device_response.device_code);
            try poll_body.appendSlice(self.allocator, "&client_id=");
            try appendUrlEncoded(self.allocator, &poll_body, self.config.client_id);

            var token_response = try http_client.post(
                self.config.token_endpoint,
                poll_body.items,
                "application/x-www-form-urlencoded",
            );
            defer token_response.deinit();

            const token_parsed = try json.parseFromSlice(json.Value, self.allocator, token_response.body, .{});
            defer token_parsed.deinit();

            const obj = token_parsed.value.object;

            // Check for error response
            if (obj.get("error")) |err_val| {
                const err_code = err_val.string;
                if (std.mem.eql(u8, err_code, "authorization_pending")) {
                    continue;
                } else if (std.mem.eql(u8, err_code, "slow_down")) {
                    interval += 5;
                    continue;
                } else if (std.mem.eql(u8, err_code, "access_denied")) {
                    return error.AuthorizationDenied;
                } else if (std.mem.eql(u8, err_code, "expired_token")) {
                    return error.DeviceCodeExpired;
                } else {
                    return error.ServerError;
                }
            }

            // Success - parse token
            return try Token.fromJsonValue(self.allocator, token_parsed.value);
        }

        // If we exit the loop without returning, max iterations was exceeded
        return error.DeviceCodeExpired;
    }

    /// Perform Authorization Code Flow with PKCE
    ///
    /// This flow:
    /// 1. Start local callback server
    /// 2. Generate PKCE and state
    /// 3. Open browser for authorization
    /// 4. Wait for callback with authorization code
    /// 5. Exchange code for token
    pub fn authorize(self: *OAuthClient) !Token {
        // Generate PKCE
        const pkce_pair = Pkce.generate();

        // Generate state for CSRF protection
        var state_bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&state_bytes);
        var state: [22]u8 = undefined;
        _ = std.base64.url_safe_no_pad.Encoder.encode(&state, &state_bytes);

        // Start callback server
        var server = try CallbackServer.init(self.allocator, 0);
        defer server.deinit();

        const callback_url = try server.getCallbackUrl(self.allocator);
        defer self.allocator.free(callback_url);

        // Build authorization URL
        const auth_url = try callback.buildAuthorizationUrl(
            self.allocator,
            self.config.authorization_endpoint,
            self.config.client_id,
            callback_url,
            self.config.scope,
            &state,
            pkce_pair.getChallenge(),
        );
        defer self.allocator.free(auth_url);

        // Open browser
        var stderr_writer2 = std.fs.File.stderr().writer(&.{});
        const stderr2 = &stderr_writer2.interface;
        try stderr2.print("\nOpening browser for authorization...\n", .{});
        try stderr2.print("If the browser doesn't open, visit:\n{s}\n\n", .{auth_url});

        callback.openBrowser(auth_url) catch {};

        // Wait for callback
        var result = try server.waitForCallback(120); // 2 minute timeout
        defer result.deinit();

        // Verify state
        if (result.state) |callback_state| {
            if (!std.mem.eql(u8, callback_state, &state)) {
                return error.InvalidState;
            }
        }

        // Check for error
        if (result.error_code != null) {
            return error.AuthorizationDenied;
        }

        const code = result.code orelse return error.ServerError;

        // Exchange code for token
        return try self.exchangeCode(code, pkce_pair.getVerifier(), callback_url);
    }

    /// Exchange an authorization code for a token
    pub fn exchangeCode(self: *OAuthClient, code: []const u8, verifier: []const u8, redirect_uri: []const u8) !Token {
        var http_client = HttpClient.init(self.allocator);
        defer http_client.deinit();

        var body: std.ArrayListUnmanaged(u8) = .{};
        defer body.deinit(self.allocator);

        try body.appendSlice(self.allocator, "grant_type=authorization_code");
        try body.appendSlice(self.allocator, "&code=");
        try appendUrlEncoded(self.allocator, &body, code);
        try body.appendSlice(self.allocator, "&redirect_uri=");
        try appendUrlEncoded(self.allocator, &body, redirect_uri);
        try body.appendSlice(self.allocator, "&client_id=");
        try appendUrlEncoded(self.allocator, &body, self.config.client_id);
        try body.appendSlice(self.allocator, "&code_verifier=");
        try appendUrlEncoded(self.allocator, &body, verifier);

        if (self.config.client_secret) |secret| {
            try body.appendSlice(self.allocator, "&client_secret=");
            try appendUrlEncoded(self.allocator, &body, secret);
        }

        var response = try http_client.post(
            self.config.token_endpoint,
            body.items,
            "application/x-www-form-urlencoded",
        );
        defer response.deinit();

        if (response.status != 200) {
            return error.ServerError;
        }

        return try Token.fromJson(self.allocator, response.body);
    }

    /// Refresh an access token using a refresh token
    pub fn refreshToken(self: *OAuthClient, refresh_token: []const u8) !Token {
        var http_client = HttpClient.init(self.allocator);
        defer http_client.deinit();

        var body: std.ArrayListUnmanaged(u8) = .{};
        defer body.deinit(self.allocator);

        try body.appendSlice(self.allocator, "grant_type=refresh_token");
        try body.appendSlice(self.allocator, "&refresh_token=");
        try appendUrlEncoded(self.allocator, &body, refresh_token);
        try body.appendSlice(self.allocator, "&client_id=");
        try appendUrlEncoded(self.allocator, &body, self.config.client_id);

        if (self.config.client_secret) |secret| {
            try body.appendSlice(self.allocator, "&client_secret=");
            try appendUrlEncoded(self.allocator, &body, secret);
        }

        var response = try http_client.post(
            self.config.token_endpoint,
            body.items,
            "application/x-www-form-urlencoded",
        );
        defer response.deinit();

        if (response.status != 200) {
            return error.ServerError;
        }

        return try Token.fromJson(self.allocator, response.body);
    }

    /// Save a token to storage
    pub fn saveToken(self: *OAuthClient, key: []const u8, token: Token) !void {
        try self.storage.save(key, token);
    }

    /// Get a token from storage
    pub fn getToken(self: *OAuthClient, key: []const u8) !?Token {
        return try self.storage.load(self.allocator, key);
    }

    /// Delete a token from storage
    pub fn deleteToken(self: *OAuthClient, key: []const u8) !void {
        try self.storage.delete(key);
    }

    fn parseDeviceResponse(allocator: Allocator, value: json.Value) !DeviceAuthorizationResponse {
        // Validate input is an object
        if (value != .object) return error.ServerError;
        const obj = value.object;

        // Validate required fields exist and have correct types
        const device_code_val = obj.get("device_code") orelse return error.ServerError;
        if (device_code_val != .string) return error.ServerError;

        const user_code_val = obj.get("user_code") orelse return error.ServerError;
        if (user_code_val != .string) return error.ServerError;

        const verification_uri_val = obj.get("verification_uri") orelse return error.ServerError;
        if (verification_uri_val != .string) return error.ServerError;

        const expires_in_val = obj.get("expires_in") orelse return error.ServerError;
        if (expires_in_val != .integer) return error.ServerError;

        // Safe integer cast with validation
        const expires_in_raw = expires_in_val.integer;
        if (expires_in_raw < 0 or expires_in_raw > std.math.maxInt(u64)) {
            return error.ServerError;
        }
        const expires_in: u64 = @intCast(expires_in_raw);

        // Parse optional interval with safe cast
        var interval: u64 = 5; // default
        if (obj.get("interval")) |iv| {
            if (iv == .integer) {
                const interval_raw = iv.integer;
                if (interval_raw > 0 and interval_raw <= 300) { // max 5 minutes
                    interval = @intCast(interval_raw);
                }
            }
        }

        // Parse optional verification_uri_complete
        var uri_complete: ?[]const u8 = null;
        if (obj.get("verification_uri_complete")) |uri| {
            if (uri == .string) {
                uri_complete = try allocator.dupe(u8, uri.string);
            }
        }
        errdefer if (uri_complete) |uc| allocator.free(uc);

        // Allocate all required fields with proper errdefer cleanup
        const device_code = try allocator.dupe(u8, device_code_val.string);
        errdefer allocator.free(device_code);

        const user_code = try allocator.dupe(u8, user_code_val.string);
        errdefer allocator.free(user_code);

        const verification_uri = try allocator.dupe(u8, verification_uri_val.string);
        // No errdefer needed - this is the last allocation, success path

        return .{
            .allocator = allocator,
            .device_code = device_code,
            .user_code = user_code,
            .verification_uri = verification_uri,
            .verification_uri_complete = uri_complete,
            .expires_in = expires_in,
            .interval = interval,
        };
    }
};

/// Token refresher with automatic refresh and cross-process locking
pub const TokenRefresher = struct {
    allocator: Allocator,
    client: *OAuthClient,
    lock_manager: ?RefreshLockManager,
    /// Refresh threshold as fraction of token lifetime (0.0-1.0)
    refresh_threshold: f64,

    /// Create a new token refresher
    pub fn init(allocator: Allocator, client: *OAuthClient) TokenRefresher {
        return .{
            .allocator = allocator,
            .client = client,
            .lock_manager = null,
            .refresh_threshold = 0.1, // Refresh at 10% remaining lifetime
        };
    }

    /// Enable cross-process locking
    pub fn withFileLocking(self: *TokenRefresher, app_name: []const u8) !void {
        self.lock_manager = try RefreshLockManager.init(self.allocator, app_name);
    }

    pub fn deinit(self: *TokenRefresher) void {
        if (self.lock_manager) |*lm| {
            lm.deinit();
        }
    }

    /// Get a valid token, refreshing if necessary
    ///
    /// This is the primary method for obtaining tokens. It:
    /// 1. Loads the token from storage
    /// 2. Checks if it's expired or about to expire
    /// 3. Refreshes if needed (with cross-process locking if enabled)
    /// 4. Returns a valid token
    pub fn getValidToken(self: *TokenRefresher, key: []const u8) !Token {
        return self.getValidTokenWithThreshold(key, self.refresh_threshold);
    }

    /// Get a valid token with a custom refresh threshold
    ///
    /// threshold: Fraction of lifetime at which to refresh (0.0-1.0)
    /// - 0.0: Only refresh when expired
    /// - 0.5: Refresh when 50% of lifetime remains
    /// - 0.8: Refresh when 20% of lifetime remains
    pub fn getValidTokenWithThreshold(self: *TokenRefresher, key: []const u8, threshold: f64) !Token {
        var token = (try self.client.getToken(key)) orelse return error.TokenNotFound;

        // Check if refresh is needed
        const needs_refresh = blk: {
            if (token.isExpired()) break :blk true;
            if (token.remainingLifetimeFraction()) |fraction| {
                if (fraction <= threshold) break :blk true;
            }
            break :blk false;
        };

        if (!needs_refresh) {
            return token;
        }

        // Need to refresh
        const refresh_token = token.refresh_token orelse {
            token.deinit();
            return error.NoRefreshToken;
        };

        // Acquire lock if enabled
        var lock_guard: ?lock.RefreshLock = null;
        if (self.lock_manager) |*lm| {
            lock_guard = try lm.acquire(key);
        }
        defer if (lock_guard) |*lg| lg.release();

        // Check again after acquiring lock (another process might have refreshed)
        if (self.lock_manager != null) {
            token.deinit();
            token = (try self.client.getToken(key)) orelse return error.TokenNotFound;

            const still_needs_refresh = blk: {
                if (token.isExpired()) break :blk true;
                if (token.remainingLifetimeFraction()) |fraction| {
                    if (fraction <= threshold) break :blk true;
                }
                break :blk false;
            };

            if (!still_needs_refresh) {
                return token;
            }
        }

        // Perform refresh
        var new_token = try self.client.refreshToken(refresh_token);
        errdefer new_token.deinit();

        // Preserve refresh token if not included in response
        if (new_token.refresh_token == null and token.refresh_token != null) {
            new_token.refresh_token = try self.allocator.dupe(u8, token.refresh_token.?);
        }

        // Save new token
        try self.client.saveToken(key, new_token);

        token.deinit();
        return new_token;
    }
};

/// Re-export appendUrlEncoded from callback module to avoid duplication
const appendUrlEncoded = callback.appendUrlEncoded;

test "OAuthConfig GitHub preset" {
    const config = OAuthConfig.github("test-client-id", "repo user");

    try std.testing.expectEqualStrings("test-client-id", config.client_id);
    try std.testing.expectEqualStrings("https://github.com/login/oauth/authorize", config.authorization_endpoint);
    try std.testing.expectEqualStrings("https://github.com/login/oauth/access_token", config.token_endpoint);
    try std.testing.expect(config.device_authorization_endpoint != null);
    try std.testing.expectEqualStrings("repo user", config.scope.?);
}

test "OAuthConfig Google preset" {
    const config = OAuthConfig.google("google-client-id", "openid email");

    try std.testing.expectEqualStrings("google-client-id", config.client_id);
    try std.testing.expectEqualStrings("https://accounts.google.com/o/oauth2/v2/auth", config.authorization_endpoint);
    try std.testing.expect(config.device_authorization_endpoint != null);
}

test "OAuthConfig Microsoft preset" {
    const config = OAuthConfig.microsoft("ms-client-id", "common", "user.read");

    try std.testing.expectEqualStrings("ms-client-id", config.client_id);
    try std.testing.expect(std.mem.indexOf(u8, config.authorization_endpoint, "microsoftonline.com") != null);
}

test "OAuthConfig Tuist preset" {
    const config = OAuthConfig.tuist("tuist-client-id", "project:read");

    try std.testing.expectEqualStrings("tuist-client-id", config.client_id);
    try std.testing.expect(std.mem.indexOf(u8, config.authorization_endpoint, "tuist.io") != null);
}

test "OAuthClient initialization" {
    const allocator = std.testing.allocator;

    var storage = session.MemoryStorage.init(allocator);
    defer storage.deinit();

    const config = OAuthConfig.github("test-client", null);
    var client = OAuthClient.init(allocator, config, storage.storage());
    defer client.deinit();

    try std.testing.expectEqualStrings("test-client", client.config.client_id);
}

test "OAuthClient token storage" {
    const allocator = std.testing.allocator;

    var storage = session.MemoryStorage.init(allocator);
    defer storage.deinit();

    const config = OAuthConfig.github("test-client", null);
    var client = OAuthClient.init(allocator, config, storage.storage());
    defer client.deinit();

    var token = try Token.init(allocator, "test_access_token", "Bearer");
    defer token.deinit();

    try client.saveToken("test_key", token);

    var loaded = (try client.getToken("test_key")).?;
    defer loaded.deinit();

    try std.testing.expectEqualStrings("test_access_token", loaded.access_token);
}

test "OAuthConfigOwned: allocation and cleanup without leaks" {
    const allocator = std.testing.allocator;

    var owned = try OAuthConfig.custom(
        allocator,
        "test-client-id",
        "https://example.com/authorize",
        "https://example.com/token",
        "http://127.0.0.1/callback",
        "read write",
        "https://example.com/device",
    );
    defer owned.deinit();

    try std.testing.expectEqualStrings("test-client-id", owned.client_id);
    try std.testing.expectEqualStrings("https://example.com/authorize", owned.authorization_endpoint);
    try std.testing.expectEqualStrings("read write", owned.scope.?);
    try std.testing.expectEqualStrings("https://example.com/device", owned.device_authorization_endpoint.?);
}

test "OAuthConfigOwned: toConfig borrows correctly" {
    const allocator = std.testing.allocator;

    var owned = try OAuthConfig.custom(
        allocator,
        "borrowed-client",
        "https://example.com/auth",
        "https://example.com/token",
        "http://127.0.0.1/callback",
        null,
        null,
    );
    defer owned.deinit();

    const config = owned.toConfig();

    // Config borrows from owned - verify same pointers
    try std.testing.expect(config.client_id.ptr == owned.client_id.ptr);
    try std.testing.expect(config.authorization_endpoint.ptr == owned.authorization_endpoint.ptr);
    try std.testing.expect(config.scope == null);
    try std.testing.expect(config.device_authorization_endpoint == null);
}

test "configFromFormula: with public client without leaks" {
    const allocator = std.testing.allocator;

    // First, ensure builtin formulas are clean
    formulas.deinitBuiltinFormulas();

    // Create a test formula with public clients
    const json_formula =
        \\{
        \\  "id": "test-provider",
        \\  "label": "Test",
        \\  "flows": ["device_code"],
        \\  "endpoints": {
        \\    "authorize": "https://test.com/authorize",
        \\    "token": "https://test.com/token",
        \\    "device": "https://test.com/device"
        \\  },
        \\  "scope": "default-scope",
        \\  "public_clients": [
        \\    {"name": "default", "id": "default-id", "secret": "default-secret"}
        \\  ]
        \\}
    ;

    var formula_owned = try formulas.loadFromJsonSlice(allocator, json_formula);
    defer formula_owned.deinit();

    // Test using default public client
    var config = try configFromFormula(
        allocator,
        formula_owned.asConst(),
        null, // No override - should use public client
        null,
        "http://127.0.0.1/callback",
        null, // No scope override
    );
    defer config.deinit();

    try std.testing.expectEqualStrings("default-id", config.client_id);
    try std.testing.expectEqualStrings("default-secret", config.client_secret.?);
    try std.testing.expectEqualStrings("default-scope", config.scope.?);
    try std.testing.expectEqualStrings("https://test.com/device", config.device_authorization_endpoint.?);
}

test "configFromFormula: with client_id override without leaks" {
    const allocator = std.testing.allocator;

    const json_formula =
        \\{
        \\  "id": "test",
        \\  "label": "Test",
        \\  "flows": ["device_code"],
        \\  "endpoints": {
        \\    "authorize": "https://test.com/authorize",
        \\    "token": "https://test.com/token"
        \\  },
        \\  "public_clients": [
        \\    {"name": "default", "id": "default-id", "secret": "default-secret"}
        \\  ]
        \\}
    ;

    var formula_owned = try formulas.loadFromJsonSlice(allocator, json_formula);
    defer formula_owned.deinit();

    // Test with client_id override
    var config = try configFromFormula(
        allocator,
        formula_owned.asConst(),
        "override-id", // Override client ID
        "override-secret", // Override secret
        "http://127.0.0.1/callback",
        "custom-scope",
    );
    defer config.deinit();

    try std.testing.expectEqualStrings("override-id", config.client_id);
    try std.testing.expectEqualStrings("override-secret", config.client_secret.?);
    try std.testing.expectEqualStrings("custom-scope", config.scope.?);
}

test "configFromFormula: missing client_id returns error" {
    const allocator = std.testing.allocator;

    const json_formula =
        \\{
        \\  "id": "no-clients",
        \\  "label": "No Clients",
        \\  "flows": ["device_code"],
        \\  "endpoints": {
        \\    "authorize": "https://test.com/authorize",
        \\    "token": "https://test.com/token"
        \\  }
        \\}
    ;

    var formula_owned = try formulas.loadFromJsonSlice(allocator, json_formula);
    defer formula_owned.deinit();

    // Should fail because no public_clients and no override
    const result = configFromFormula(
        allocator,
        formula_owned.asConst(),
        null,
        null,
        "http://127.0.0.1/callback",
        null,
    );

    try std.testing.expectError(error.MissingClientId, result);
}

test "OAuthConfig.gitlabSelfHosted: without leaks" {
    const allocator = std.testing.allocator;

    var config = try OAuthConfig.gitlabSelfHosted(
        allocator,
        "gitlab-client",
        "https://gitlab.mycompany.com",
        "api read_user",
    );
    defer config.deinit();

    try std.testing.expectEqualStrings("gitlab-client", config.client_id);
    try std.testing.expectEqualStrings("https://gitlab.mycompany.com/oauth/authorize", config.authorization_endpoint);
    try std.testing.expectEqualStrings("https://gitlab.mycompany.com/oauth/token", config.token_endpoint);
    try std.testing.expectEqualStrings("api read_user", config.scope.?);
}

test "OAuthConfig.gitlabSelfHosted: strips trailing slash" {
    const allocator = std.testing.allocator;

    var config = try OAuthConfig.gitlabSelfHosted(
        allocator,
        "gitlab-client",
        "https://gitlab.mycompany.com/",
        null,
    );
    defer config.deinit();

    try std.testing.expectEqualStrings("https://gitlab.mycompany.com/oauth/authorize", config.authorization_endpoint);
}

test "OAuthConfig.gitlabSelfHosted: rejects insecure URL" {
    const allocator = std.testing.allocator;

    const result = OAuthConfig.gitlabSelfHosted(
        allocator,
        "client",
        "http://insecure.example.com",
        null,
    );

    try std.testing.expectError(error.InsecureEndpoint, result);
}

test "validateEndpointSecurity: allows HTTPS" {
    try validateEndpointSecurity("https://example.com/oauth");
    try validateEndpointSecurity("https://sub.domain.example.com:8443/path");
}

test "validateEndpointSecurity: allows localhost HTTP" {
    try validateEndpointSecurity("http://localhost/callback");
    try validateEndpointSecurity("http://localhost:8080/callback");
    try validateEndpointSecurity("http://127.0.0.1/callback");
    try validateEndpointSecurity("http://127.0.0.1:3000/callback");
    try validateEndpointSecurity("http://[::1]/callback");
}

test "validateEndpointSecurity: rejects insecure HTTP" {
    try std.testing.expectError(error.InsecureEndpoint, validateEndpointSecurity("http://example.com/oauth"));
    try std.testing.expectError(error.InsecureEndpoint, validateEndpointSecurity("http://192.168.1.1/oauth"));
}
