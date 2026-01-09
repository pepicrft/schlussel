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

const std = @import("std");
const Allocator = std.mem.Allocator;
const http = std.http;
const json = std.json;
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

        // Parse JSON response
        const parsed = try json.parseFromSliceLeaky(ClientRegistrationResponseJson, self.allocator, response_body, .{});

        return ClientRegistrationResponse{
            .allocator = self.allocator,
            .client_id = try self.allocator.dupe(u8, parsed.client_id),
            .client_secret = if (parsed.client_secret) |s| try self.allocator.dupe(u8, s) else null,
            .client_id_issued_at = parsed.client_id_issued_at,
            .client_secret_expires_at = parsed.client_secret_expires_at,
            .registration_access_token = if (parsed.registration_access_token) |s| try self.allocator.dupe(u8, s) else null,
            .registration_client_uri = if (parsed.registration_client_uri) |s| try self.allocator.dupe(u8, s) else null,
        };
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

    /// Read client configuration from the registration endpoint
    pub fn read(self: *DynamicRegistration, registration_access_token: []const u8) !ClientRegistrationResponse {
        _ = registration_access_token;
        _ = self;
        // TODO: Implement GET request to registration endpoint
        return error.NotImplemented;
    }

    /// Update client configuration at the authorization server
    pub fn update(self: *DynamicRegistration, registration_access_token: []const u8, metadata: ClientMetadata) !ClientRegistrationResponse {
        _ = registration_access_token;
        _ = metadata;
        _ = self;
        // TODO: Implement PUT request to registration endpoint
        return error.NotImplemented;
    }

    /// Delete client registration
    pub fn delete(self: *DynamicRegistration, registration_access_token: []const u8) !void {
        _ = registration_access_token;
        _ = self;
        // TODO: Implement DELETE request to registration endpoint
        return error.NotImplemented;
    }
};
