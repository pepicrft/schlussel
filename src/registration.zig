//! OAuth 2.0 Dynamic Client Registration (RFC 7591)
//!
//! This module provides functionality for dynamically registering clients
//! with OAuth 2.0 authorization servers.
//!
//! ## Example
//!
//! ```zig
//! var registration = try DynamicRegistration.init(allocator, "https://auth.example.com/register");
//! defer registration.deinit();
//!
//! // Register a new client
//! var client_metadata = try ClientMetadata.init(allocator);
//! defer client_metadata.deinit();
//! client_metadata.client_name = "My Application";
//! client_metadata.redirect_uris = &[_][]const u8{"https://example.com/callback"};
//! client_metadata.grant_types = &[_][]const u8{"authorization_code", "refresh_token"};
//! client_metadata.response_types = &[_][]const u8{"code"};
//!
//! var response = try registration.register(client_metadata);
//! defer response.deinit();
//!
//! std.debug.print("Client ID: {s}\n", .{response.client_id});
//! ```
//!
//! For read/update/delete, initialize `DynamicRegistration` with the
//! `registration_client_uri` returned during registration (not the initial
//! registration endpoint).

const std = @import("std");
const Allocator = std.mem.Allocator;
const http = std.http;
const json = std.json;
const net = std.net;
const Uri = std.Uri;

/// JSON parsing struct for client registration response
const ClientRegistrationResponseJson = struct {
    client_id: []const u8,
    client_secret: ?[]const u8 = null,
    client_id_issued_at: ?i64 = null,
    client_secret_expires_at: ?i64 = null,
    registration_access_token: ?[]const u8 = null,
    registration_client_uri: ?[]const u8 = null,
};

/// Metadata required for registering an OAuth client
pub const ClientMetadata = struct {
    allocator: Allocator,

    /// Human-readable name of the client
    client_name: []const u8 = "",
    /// URL of the logo for the client
    client_uri: ?[]const u8 = null,
    /// URL of the logo for the client
    logo_uri: ?[]const u8 = null,

    /// Array of redirection URIs
    redirect_uris: []const []const u8 = &.{},
    /// Array of grant types the client can use
    grant_types: []const []const u8 = &.{},
    /// Array of response types the client can use
    response_types: []const []const u8 = &.{},
    /// Scope of the registration request
    scope: ?[]const u8 = null,

    /// Array of email addresses
    contacts: []const []const u8 = &.{},
    /// URL of the terms of service
    tos_uri: ?[]const u8 = null,
    /// URL of the policy document
    policy_uri: ?[]const u8 = null,
    /// URL of the logo for the client
    jwks_uri: ?[]const u8 = null,

    /// JWK Set document containing the client's public keys
    jwks: ?[]const u8 = null,
    /// Algorithm used for signing tokens
    token_endpoint_auth_method: ?[]const u8 = null,
    /// Algorithm used for signing tokens
    token_endpoint_auth_signing_alg: ?[]const u8 = null,
    /// Algorithm used for signing tokens
    id_token_signed_response_alg: ?[]const u8 = null,
    /// Algorithm used for encrypting tokens
    id_token_encrypted_response_alg: ?[]const u8 = null,
    /// Algorithm used for encrypting tokens
    id_token_encrypted_response_enc: ?[]const u8 = null,
    /// Algorithm used for signing tokens
    userinfo_signed_response_alg: ?[]const u8 = null,
    /// Algorithm used for encrypting tokens
    userinfo_encrypted_response_alg: ?[]const u8 = null,
    /// Algorithm used for encrypting tokens
    userinfo_encrypted_response_enc: ?[]const u8 = null,
    /// Algorithm used for signing tokens
    request_object_signing_alg: ?[]const u8 = null,
    /// Algorithm used for encrypting tokens
    request_object_encryption_alg: ?[]const u8 = null,
    /// Algorithm used for encrypting tokens
    request_object_encryption_enc: ?[]const u8 = null,
    /// Default maximum authentication lifetime
    default_max_age: ?u64 = null,
    /// Authentication lifetime for the session
    require_auth_time: ?bool = null,
    /// Default ACR values
    default_acr_values: ?[]const []const u8 = null,
    /// Initiate login URI
    initiate_login_uri: ?[]const u8 = null,
    /// Request URIs
    request_uris: ?[]const []const u8 = null,
    /// Front-channel logout URI
    frontchannel_logout_uri: ?[]const u8 = null,
    /// Front-channel logout session required
    frontchannel_logout_session_required: ?bool = null,
    /// Back-channel logout URI
    backchannel_logout_uri: ?[]const u8 = null,
    /// Back-channel logout session required
    backchannel_logout_session_required: ?bool = null,

    pub fn init(allocator: Allocator) !ClientMetadata {
        return .{
            .allocator = allocator,
            .redirect_uris = &[0][]const u8{},
            .grant_types = &[0][]const u8{},
            .response_types = &[0][]const u8{},
            .contacts = &[0][]const u8{},
        };
    }

    pub fn deinit(self: *ClientMetadata) void {
        // Note: We only free owned strings, not the slices pointing to static data
        if (self.client_uri) |s| self.allocator.free(s);
        if (self.logo_uri) |s| self.allocator.free(s);
        if (self.tos_uri) |s| self.allocator.free(s);
        if (self.policy_uri) |s| self.allocator.free(s);
        if (self.jwks_uri) |s| self.allocator.free(s);
        if (self.jwks) |s| self.allocator.free(s);
        if (self.token_endpoint_auth_method) |s| self.allocator.free(s);
        if (self.scope) |s| self.allocator.free(s);
        if (self.initiate_login_uri) |s| self.allocator.free(s);
        if (self.frontchannel_logout_uri) |s| self.allocator.free(s);
        if (self.backchannel_logout_uri) |s| self.allocator.free(s);
    }
};

/// Response from a successful client registration
pub const ClientRegistrationResponse = struct {
    allocator: Allocator,

    /// Client identifier issued by the server
    client_id: []const u8,
    /// Client secret (if confidential client)
    client_secret: ?[]const u8 = null,
    /// Client identifier issued at time
    client_id_issued_at: ?i64 = null,
    /// Client secret expiration time
    client_secret_expires_at: ?i64 = null,

    /// Registration access token
    registration_access_token: ?[]const u8 = null,
    /// Registration client URI
    registration_client_uri: ?[]const u8 = null,

    pub fn deinit(self: *ClientRegistrationResponse) void {
        self.allocator.free(self.client_id);
        if (self.client_secret) |s| self.allocator.free(s);
        if (self.registration_access_token) |s| self.allocator.free(s);
        if (self.registration_client_uri) |s| self.allocator.free(s);
    }
};

/// Dynamic client registration client
pub const DynamicRegistration = struct {
    allocator: Allocator,
    registration_endpoint: []const u8,

    /// HTTP client for making requests
    http_client: *http.Client,

    pub fn init(allocator: Allocator, registration_endpoint: []const u8) !DynamicRegistration {
        // Validate that the endpoint uses HTTPS
        if (!std.mem.startsWith(u8, registration_endpoint, "https://") and
            !std.mem.startsWith(u8, registration_endpoint, "http://localhost"))
        {
            return error.InsecureEndpoint;
        }

        const client = try allocator.create(http.Client);
        client.* = .{ .allocator = allocator };

        return .{
            .allocator = allocator,
            .registration_endpoint = registration_endpoint,
            .http_client = client,
        };
    }

    pub fn deinit(self: *DynamicRegistration) void {
        self.http_client.deinit();
        self.allocator.destroy(self.http_client);
    }

    /// Register a new client with the authorization server
    pub fn register(self: *DynamicRegistration, metadata: ClientMetadata) !ClientRegistrationResponse {
        // Prepare request body
        var body_buffer: std.ArrayList(u8) = .empty;
        defer body_buffer.deinit(self.allocator);

        try self.writeMetadataJson(body_buffer.writer(self.allocator), metadata);

        // Create response body storage
        var response_writer = std.Io.Writer.Allocating.init(self.allocator);
        errdefer response_writer.deinit();

        // Make HTTP request
        const result = try self.http_client.fetch(.{
            .location = .{ .url = self.registration_endpoint },
            .method = .POST,
            .payload = body_buffer.items,
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "application/json" },
                .{ .name = "Accept", .value = "application/json" },
            },
            .response_writer = &response_writer.writer,
        });

        // Check response
        if (result.status != .created and result.status != .ok) {
            return error.RegistrationFailed;
        }

        const response_body = try response_writer.toOwnedSlice();
        defer self.allocator.free(response_body);

        return self.parseRegistrationResponse(response_body);
    }

    /// Write client metadata as JSON
    fn writeMetadataJson(self: *DynamicRegistration, writer: anytype, metadata: ClientMetadata) !void {
        try writer.writeAll("{");

        var first = true;

        // Required fields
        if (metadata.redirect_uris.len > 0) {
            try self.writeComma(&first, writer);
            try writer.print("\"redirect_uris\": [", .{});
            for (metadata.redirect_uris, 0..) |uri, i| {
                if (i > 0) try writer.writeAll(",");
                try writer.print("\"{s}\"", .{uri});
            }
            try writer.writeAll("]");
        }

        // Optional fields
        if (metadata.client_name.len > 0) {
            try self.writeComma(&first, writer);
            try writer.print("\"client_name\": \"{s}\"", .{metadata.client_name});
        }

        if (metadata.client_uri) |uri| {
            try self.writeComma(&first, writer);
            try writer.print("\"client_uri\": \"{s}\"", .{uri});
        }

        if (metadata.logo_uri) |uri| {
            try self.writeComma(&first, writer);
            try writer.print("\"logo_uri\": \"{s}\"", .{uri});
        }

        if (metadata.grant_types.len > 0) {
            try self.writeComma(&first, writer);
            try writer.writeAll("\"grant_types\": [");
            for (metadata.grant_types, 0..) |gt, i| {
                if (i > 0) try writer.writeAll(",");
                try writer.print("\"{s}\"", .{gt});
            }
            try writer.writeAll("]");
        }

        if (metadata.response_types.len > 0) {
            try self.writeComma(&first, writer);
            try writer.writeAll("\"response_types\": [");
            for (metadata.response_types, 0..) |rt, i| {
                if (i > 0) try writer.writeAll(",");
                try writer.print("\"{s}\"", .{rt});
            }
            try writer.writeAll("]");
        }

        if (metadata.scope) |scope| {
            try self.writeComma(&first, writer);
            try writer.print("\"scope\": \"{s}\"", .{scope});
        }

        if (metadata.token_endpoint_auth_method) |method| {
            try self.writeComma(&first, writer);
            try writer.print("\"token_endpoint_auth_method\": \"{s}\"", .{method});
        }

        try writer.writeAll("}");
    }

    fn writeComma(_: *DynamicRegistration, first: *bool, writer: anytype) !void {
        if (!first.*) {
            try writer.writeAll(",");
        }
        first.* = false;
    }

    fn buildAuthHeader(self: *DynamicRegistration, registration_access_token: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "Bearer {s}", .{registration_access_token});
    }

    fn parseRegistrationResponse(self: *DynamicRegistration, response_body: []const u8) !ClientRegistrationResponse {
        var parsed = try json.parseFromSlice(ClientRegistrationResponseJson, self.allocator, response_body, .{});
        defer parsed.deinit();

        return ClientRegistrationResponse{
            .allocator = self.allocator,
            .client_id = try self.allocator.dupe(u8, parsed.value.client_id),
            .client_secret = if (parsed.value.client_secret) |s| try self.allocator.dupe(u8, s) else null,
            .client_id_issued_at = parsed.value.client_id_issued_at,
            .client_secret_expires_at = parsed.value.client_secret_expires_at,
            .registration_access_token = if (parsed.value.registration_access_token) |s| try self.allocator.dupe(u8, s) else null,
            .registration_client_uri = if (parsed.value.registration_client_uri) |s| try self.allocator.dupe(u8, s) else null,
        };
    }

    /// Read client configuration from the registration endpoint
    pub fn read(self: *DynamicRegistration, registration_access_token: []const u8) !ClientRegistrationResponse {
        const auth_header = try self.buildAuthHeader(registration_access_token);
        defer self.allocator.free(auth_header);

        var response_writer = std.Io.Writer.Allocating.init(self.allocator);
        errdefer response_writer.deinit();

        const result = try self.http_client.fetch(.{
            .location = .{ .url = self.registration_endpoint },
            .method = .GET,
            .extra_headers = &.{
                .{ .name = "Authorization", .value = auth_header },
                .{ .name = "Accept", .value = "application/json" },
            },
            .response_writer = &response_writer.writer,
        });

        if (result.status != .ok) {
            return error.RegistrationFailed;
        }

        const response_body = try response_writer.toOwnedSlice();
        defer self.allocator.free(response_body);

        return self.parseRegistrationResponse(response_body);
    }

    /// Update client configuration at the authorization server
    pub fn update(self: *DynamicRegistration, registration_access_token: []const u8, metadata: ClientMetadata) !ClientRegistrationResponse {
        // Prepare request body
        var body_buffer: std.ArrayList(u8) = .empty;
        defer body_buffer.deinit(self.allocator);

        try self.writeMetadataJson(body_buffer.writer(self.allocator), metadata);

        const auth_header = try self.buildAuthHeader(registration_access_token);
        defer self.allocator.free(auth_header);

        var response_writer = std.Io.Writer.Allocating.init(self.allocator);
        errdefer response_writer.deinit();

        const result = try self.http_client.fetch(.{
            .location = .{ .url = self.registration_endpoint },
            .method = .PUT,
            .payload = body_buffer.items,
            .extra_headers = &.{
                .{ .name = "Authorization", .value = auth_header },
                .{ .name = "Content-Type", .value = "application/json" },
                .{ .name = "Accept", .value = "application/json" },
            },
            .response_writer = &response_writer.writer,
        });

        if (result.status != .ok) {
            return error.RegistrationFailed;
        }

        const response_body = try response_writer.toOwnedSlice();
        defer self.allocator.free(response_body);

        return self.parseRegistrationResponse(response_body);
    }

    /// Delete client registration
    pub fn delete(self: *DynamicRegistration, registration_access_token: []const u8) !void {
        const auth_header = try self.buildAuthHeader(registration_access_token);
        defer self.allocator.free(auth_header);

        var response_writer = std.Io.Writer.Allocating.init(self.allocator);
        errdefer response_writer.deinit();

        const result = try self.http_client.fetch(.{
            .location = .{ .url = self.registration_endpoint },
            .method = .DELETE,
            .extra_headers = &.{
                .{ .name = "Authorization", .value = auth_header },
                .{ .name = "Accept", .value = "application/json" },
            },
            .response_writer = &response_writer.writer,
        });

        if (result.status != .ok and result.status != .no_content) {
            return error.RegistrationFailed;
        }
    }
};

test "dynamic registration metadata JSON includes required and optional fields" {
    const allocator = std.testing.allocator;

    var registration = try DynamicRegistration.init(allocator, "http://localhost/register");
    defer registration.deinit();

    var metadata = try ClientMetadata.init(allocator);
    defer metadata.deinit();

    metadata.client_name = "Test App";
    metadata.redirect_uris = &[_][]const u8{"https://example.com/callback"};
    metadata.grant_types = &[_][]const u8{ "authorization_code", "refresh_token" };
    metadata.response_types = &[_][]const u8{"code"};
    metadata.scope = try allocator.dupe(u8, "read write");
    metadata.token_endpoint_auth_method = try allocator.dupe(u8, "client_secret_basic");

    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(allocator);

    try registration.writeMetadataJson(buffer.writer(allocator), metadata);

    const expected =
        "{\"redirect_uris\": [\"https://example.com/callback\"],\"client_name\": \"Test App\",\"grant_types\": [\"authorization_code\",\"refresh_token\"],\"response_types\": [\"code\"],\"scope\": \"read write\",\"token_endpoint_auth_method\": \"client_secret_basic\"}";
    try std.testing.expectEqualStrings(expected, buffer.items);
}

test "dynamic registration metadata JSON omits empty optional fields" {
    const allocator = std.testing.allocator;

    var registration = try DynamicRegistration.init(allocator, "http://localhost/register");
    defer registration.deinit();

    var metadata = try ClientMetadata.init(allocator);
    defer metadata.deinit();

    metadata.redirect_uris = &[_][]const u8{"https://example.com/callback"};

    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(allocator);

    try registration.writeMetadataJson(buffer.writer(allocator), metadata);

    const expected = "{\"redirect_uris\": [\"https://example.com/callback\"]}";
    try std.testing.expectEqualStrings(expected, buffer.items);
}

test "dynamic registration response parsing handles optional fields" {
    const allocator = std.testing.allocator;

    var registration = try DynamicRegistration.init(allocator, "http://localhost/register");
    defer registration.deinit();

    const response_json =
        "{\"client_id\":\"abc\",\"client_secret\":\"shh\",\"client_id_issued_at\":1234,\"client_secret_expires_at\":5678,\"registration_access_token\":\"rat\",\"registration_client_uri\":\"https://example.com/clients/abc\"}";

    var response = try registration.parseRegistrationResponse(response_json);
    defer response.deinit();

    try std.testing.expectEqualStrings("abc", response.client_id);
    try std.testing.expectEqualStrings("shh", response.client_secret.?);
    try std.testing.expectEqual(@as(i64, 1234), response.client_id_issued_at.?);
    try std.testing.expectEqual(@as(i64, 5678), response.client_secret_expires_at.?);
    try std.testing.expectEqualStrings("rat", response.registration_access_token.?);
    try std.testing.expectEqualStrings("https://example.com/clients/abc", response.registration_client_uri.?);
}

test "dynamic registration response parsing handles minimal fields" {
    const allocator = std.testing.allocator;

    var registration = try DynamicRegistration.init(allocator, "http://localhost/register");
    defer registration.deinit();

    const response_json = "{\"client_id\":\"abc\"}";

    var response = try registration.parseRegistrationResponse(response_json);
    defer response.deinit();

    try std.testing.expectEqualStrings("abc", response.client_id);
    try std.testing.expect(response.client_secret == null);
    try std.testing.expect(response.client_id_issued_at == null);
    try std.testing.expect(response.client_secret_expires_at == null);
    try std.testing.expect(response.registration_access_token == null);
    try std.testing.expect(response.registration_client_uri == null);
}

const TestRegistrationServer = struct {
    server: net.Server,
    port: u16,
    stats: Stats = .{},
    shutdown_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    active: bool = true,

    const ServerError = error{
        InvalidRequest,
        ConnectionClosed,
    };

    const Stats = struct {
        saw_post: bool = false,
        saw_get: bool = false,
        saw_put: bool = false,
        saw_delete: bool = false,
        saw_auth_header: bool = false,
        saw_post_body: bool = false,
        saw_put_body: bool = false,
        err: ?anyerror = null,
    };

    fn init() !TestRegistrationServer {
        const address = net.Address.initIp6(.{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 }, 0, 0, 0);
        const server = try address.listen(.{
            .reuse_address = true,
        });
        const port = server.listen_address.getPort();
        return .{
            .server = server,
            .port = port,
        };
    }

    fn deinit(self: *TestRegistrationServer) void {
        if (self.active) {
            self.server.deinit();
            self.active = false;
        }
    }

    fn urlFor(self: *TestRegistrationServer, allocator: Allocator, path: []const u8) ![]const u8 {
        return std.fmt.allocPrint(allocator, "http://localhost:{d}{s}", .{ self.port, path });
    }

    fn shutdown(self: *TestRegistrationServer) void {
        self.shutdown_requested.store(true, .release);
        if (self.active) {
            self.server.deinit();
            self.active = false;
        }
    }

    fn run(
        self: *TestRegistrationServer,
        register_path: []const u8,
        client_path: []const u8,
        client_url: []const u8,
        token: []const u8,
    ) void {
        var handled: usize = 0;
        while (handled < 4 and !self.shutdown_requested.load(.acquire)) : (handled += 1) {
            var connection = self.server.accept() catch |err| {
                if (self.shutdown_requested.load(.acquire)) {
                    return;
                }
                self.stats.err = err;
                return;
            };
            defer connection.stream.close();

            var buf: [8192]u8 = undefined;
            const bytes_read = connection.stream.read(&buf) catch |err| {
                self.stats.err = err;
                return;
            };
            if (bytes_read == 0) {
                self.stats.err = ServerError.ConnectionClosed;
                return;
            }

            const request = buf[0..bytes_read];
            const first_space = std.mem.indexOfScalar(u8, request, ' ') orelse {
                self.stats.err = ServerError.InvalidRequest;
                return;
            };
            const method = request[0..first_space];
            const rest = request[first_space + 1 ..];
            const second_space = std.mem.indexOfScalar(u8, rest, ' ') orelse {
                self.stats.err = ServerError.InvalidRequest;
                return;
            };
            const path = rest[0..second_space];

            const header_end = std.mem.indexOf(u8, request, "\r\n\r\n") orelse request.len;
            const headers = request[0..header_end];
            const body = if (header_end + 4 <= request.len) request[header_end + 4 ..] else "";

            const auth_ok = std.mem.indexOf(u8, headers, "Authorization: Bearer ") != null and
                std.mem.indexOf(u8, headers, token) != null;
            const accept_json = std.mem.indexOf(u8, headers, "Accept: application/json") != null;
            const content_json = std.mem.indexOf(u8, headers, "Content-Type: application/json") != null;

            if (std.mem.eql(u8, method, "POST")) {
                if (!std.mem.eql(u8, path, register_path)) {
                    self.stats.err = ServerError.InvalidRequest;
                    return;
                }
                if (!accept_json or !content_json) {
                    self.stats.err = ServerError.InvalidRequest;
                    return;
                }
                self.stats.saw_post = true;
                if (std.mem.indexOf(u8, body, "Test App") != null) {
                    self.stats.saw_post_body = true;
                }

                var response_body_buf: [512]u8 = undefined;
                const response_body = std.fmt.bufPrint(
                    &response_body_buf,
                    "{{\"client_id\":\"abc\",\"registration_access_token\":\"{s}\",\"registration_client_uri\":\"{s}\"}}",
                    .{ token, client_url },
                ) catch |err| {
                    self.stats.err = err;
                    return;
                };

                var response_buf: [1024]u8 = undefined;
                const response = std.fmt.bufPrint(
                    &response_buf,
                    "HTTP/1.1 201 Created\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}",
                    .{ response_body.len, response_body },
                ) catch |err| {
                    self.stats.err = err;
                    return;
                };
                connection.stream.writeAll(response) catch |err| {
                    self.stats.err = err;
                    return;
                };
            } else if (std.mem.eql(u8, method, "GET")) {
                if (!std.mem.eql(u8, path, client_path)) {
                    self.stats.err = ServerError.InvalidRequest;
                    return;
                }
                if (!accept_json or !auth_ok) {
                    self.stats.err = ServerError.InvalidRequest;
                    return;
                }
                self.stats.saw_get = true;
                self.stats.saw_auth_header = self.stats.saw_auth_header or auth_ok;

                const response_body = "{\"client_id\":\"abc\"}";
                var response_buf: [256]u8 = undefined;
                const response = std.fmt.bufPrint(
                    &response_buf,
                    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}",
                    .{ response_body.len, response_body },
                ) catch |err| {
                    self.stats.err = err;
                    return;
                };
                connection.stream.writeAll(response) catch |err| {
                    self.stats.err = err;
                    return;
                };
            } else if (std.mem.eql(u8, method, "PUT")) {
                if (!std.mem.eql(u8, path, client_path)) {
                    self.stats.err = ServerError.InvalidRequest;
                    return;
                }
                if (!accept_json or !content_json or !auth_ok) {
                    self.stats.err = ServerError.InvalidRequest;
                    return;
                }
                self.stats.saw_put = true;
                self.stats.saw_auth_header = self.stats.saw_auth_header or auth_ok;
                if (std.mem.indexOf(u8, body, "Updated App") != null) {
                    self.stats.saw_put_body = true;
                }

                const response_body = "{\"client_id\":\"abc\"}";
                var response_buf: [256]u8 = undefined;
                const response = std.fmt.bufPrint(
                    &response_buf,
                    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}",
                    .{ response_body.len, response_body },
                ) catch |err| {
                    self.stats.err = err;
                    return;
                };
                connection.stream.writeAll(response) catch |err| {
                    self.stats.err = err;
                    return;
                };
            } else if (std.mem.eql(u8, method, "DELETE")) {
                if (!std.mem.eql(u8, path, client_path)) {
                    self.stats.err = ServerError.InvalidRequest;
                    return;
                }
                if (!accept_json or !auth_ok) {
                    self.stats.err = ServerError.InvalidRequest;
                    return;
                }
                self.stats.saw_delete = true;
                self.stats.saw_auth_header = self.stats.saw_auth_header or auth_ok;

                const response = "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                connection.stream.writeAll(response) catch |err| {
                    self.stats.err = err;
                    return;
                };
            } else {
                self.stats.err = ServerError.InvalidRequest;
                return;
            }

            if (self.shutdown_requested.load(.acquire)) {
                return;
            }
        }
    }
};

test "dynamic registration HTTP lifecycle" {
    // Skip this test on Windows due to flaky socket behavior in CI
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try TestRegistrationServer.init();
    defer server.deinit();

    const register_path = "/register";
    const client_path = "/clients/abc";
    const token = "rat";

    const register_url = try server.urlFor(allocator, register_path);
    defer allocator.free(register_url);
    const client_url = try server.urlFor(allocator, client_path);
    defer allocator.free(client_url);

    var thread = try std.Thread.spawn(
        .{},
        TestRegistrationServer.run,
        .{ &server, register_path, client_path, client_url, token },
    );
    var joined = false;
    defer {
        if (!joined) thread.join();
    }

    var registration_client = try DynamicRegistration.init(allocator, register_url);
    defer registration_client.deinit();

    var metadata = try ClientMetadata.init(allocator);
    defer metadata.deinit();
    metadata.client_name = "Test App";
    metadata.redirect_uris = &[_][]const u8{"https://example.com/callback"};

    var response = try registration_client.register(metadata);
    defer response.deinit();

    try std.testing.expectEqualStrings("abc", response.client_id);
    try std.testing.expectEqualStrings(token, response.registration_access_token.?);
    try std.testing.expectEqualStrings(client_url, response.registration_client_uri.?);

    var management_client = try DynamicRegistration.init(allocator, response.registration_client_uri.?);
    defer management_client.deinit();

    var read_response = try management_client.read(token);
    defer read_response.deinit();
    try std.testing.expectEqualStrings("abc", read_response.client_id);

    var update_metadata = try ClientMetadata.init(allocator);
    defer update_metadata.deinit();
    update_metadata.client_name = "Updated App";
    update_metadata.redirect_uris = &[_][]const u8{"https://example.com/callback"};

    var update_response = try management_client.update(token, update_metadata);
    defer update_response.deinit();
    try std.testing.expectEqualStrings("abc", update_response.client_id);

    try management_client.delete(token);

    server.shutdown();
    thread.join();
    joined = true;

    if (server.stats.err) |err| {
        return err;
    }
    try std.testing.expect(server.stats.saw_post);
    try std.testing.expect(server.stats.saw_get);
    try std.testing.expect(server.stats.saw_put);
    try std.testing.expect(server.stats.saw_delete);
    try std.testing.expect(server.stats.saw_post_body);
    try std.testing.expect(server.stats.saw_put_body);
    try std.testing.expect(server.stats.saw_auth_header);
}
