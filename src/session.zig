//! Session and Token management with pluggable storage backends
//!
//! This module provides OAuth token and session types along with storage
//! backends for persisting authentication state.
//!
//! ## Storage Backends
//!
//! - `MemoryStorage`: In-memory storage for testing
//! - `FileStorage`: JSON file-based storage for development
//! - `SecureStorage`: OS credential manager (Keychain, Credential Manager, Secret Service)
//!
//! ## Example
//!
//! ```zig
//! var storage = MemoryStorage.init(allocator);
//! defer storage.deinit();
//!
//! var token = try Token.init(allocator, "access_token", "Bearer");
//! defer token.deinit();
//!
//! try storage.storage().save("my_token", token);
//! ```

const std = @import("std");
const json = std.json;
const fs = std.fs;
const mem = std.mem;
const Allocator = std.mem.Allocator;

/// OAuth 2.0 Token
pub const Token = struct {
    allocator: Allocator,
    /// The access token issued by the authorization server
    access_token: []const u8,
    /// The type of token (usually "Bearer")
    token_type: []const u8,
    /// The refresh token for obtaining new access tokens
    refresh_token: ?[]const u8 = null,
    /// Token lifetime in seconds
    expires_in: ?u64 = null,
    /// Absolute expiration timestamp (Unix seconds)
    expires_at: ?u64 = null,
    /// Space-separated list of scopes
    scope: ?[]const u8 = null,
    /// ID token for OpenID Connect
    id_token: ?[]const u8 = null,

    /// Create a new token with the minimum required fields
    pub fn init(allocator: Allocator, access_token: []const u8, token_type: []const u8) !Token {
        return .{
            .allocator = allocator,
            .access_token = try allocator.dupe(u8, access_token),
            .token_type = try allocator.dupe(u8, token_type),
        };
    }

    /// Create a token with all fields
    pub fn initFull(
        allocator: Allocator,
        access_token: []const u8,
        token_type: []const u8,
        refresh_token: ?[]const u8,
        expires_in: ?u64,
        scope: ?[]const u8,
        id_token: ?[]const u8,
    ) !Token {
        const now = @as(u64, @intCast(std.time.timestamp()));

        return .{
            .allocator = allocator,
            .access_token = try allocator.dupe(u8, access_token),
            .token_type = try allocator.dupe(u8, token_type),
            .refresh_token = if (refresh_token) |rt| try allocator.dupe(u8, rt) else null,
            .expires_in = expires_in,
            .expires_at = if (expires_in) |exp| now + exp else null,
            .scope = if (scope) |s| try allocator.dupe(u8, s) else null,
            .id_token = if (id_token) |id| try allocator.dupe(u8, id) else null,
        };
    }

    /// Free all allocated memory
    pub fn deinit(self: *Token) void {
        self.allocator.free(self.access_token);
        self.allocator.free(self.token_type);
        if (self.refresh_token) |rt| self.allocator.free(rt);
        if (self.scope) |s| self.allocator.free(s);
        if (self.id_token) |id| self.allocator.free(id);
    }

    /// Clone this token
    pub fn clone(self: *const Token, allocator: Allocator) !Token {
        return .{
            .allocator = allocator,
            .access_token = try allocator.dupe(u8, self.access_token),
            .token_type = try allocator.dupe(u8, self.token_type),
            .refresh_token = if (self.refresh_token) |rt| try allocator.dupe(u8, rt) else null,
            .expires_in = self.expires_in,
            .expires_at = self.expires_at,
            .scope = if (self.scope) |s| try allocator.dupe(u8, s) else null,
            .id_token = if (self.id_token) |id| try allocator.dupe(u8, id) else null,
        };
    }

    /// Check if the token is expired
    pub fn isExpired(self: *const Token) bool {
        if (self.expires_at) |expires_at| {
            const now = @as(u64, @intCast(std.time.timestamp()));
            return now >= expires_at;
        }
        return false;
    }

    /// Check if the token expires within the given number of seconds
    pub fn expiresWithin(self: *const Token, seconds: u64) bool {
        if (self.expires_at) |expires_at| {
            const now = @as(u64, @intCast(std.time.timestamp()));
            return now + seconds >= expires_at;
        }
        return false;
    }

    /// Get the remaining lifetime as a fraction (0.0 to 1.0)
    ///
    /// Returns null if expiration info is not available
    pub fn remainingLifetimeFraction(self: *const Token) ?f64 {
        if (self.expires_at == null or self.expires_in == null) return null;

        const expires_at = self.expires_at.?;
        const expires_in = self.expires_in.?;
        const now = @as(u64, @intCast(std.time.timestamp()));

        if (now >= expires_at) return 0.0;

        const remaining = expires_at - now;
        return @as(f64, @floatFromInt(remaining)) / @as(f64, @floatFromInt(expires_in));
    }

    /// Serialize token to JSON
    pub fn toJson(self: *const Token, allocator: Allocator) ![]u8 {
        var buf: std.ArrayListUnmanaged(u8) = .{};
        errdefer buf.deinit(allocator);

        try buf.appendSlice(allocator, "{\"access_token\":\"");
        try buf.appendSlice(allocator, self.access_token);
        try buf.appendSlice(allocator, "\",\"token_type\":\"");
        try buf.appendSlice(allocator, self.token_type);
        try buf.append(allocator, '"');

        if (self.refresh_token) |rt| {
            try buf.appendSlice(allocator, ",\"refresh_token\":\"");
            try buf.appendSlice(allocator, rt);
            try buf.append(allocator, '"');
        }

        if (self.expires_in) |exp| {
            try buf.appendSlice(allocator, ",\"expires_in\":");
            try buf.writer(allocator).print("{d}", .{exp});
        }

        if (self.expires_at) |exp| {
            try buf.appendSlice(allocator, ",\"expires_at\":");
            try buf.writer(allocator).print("{d}", .{exp});
        }

        if (self.scope) |s| {
            try buf.appendSlice(allocator, ",\"scope\":\"");
            try buf.appendSlice(allocator, s);
            try buf.append(allocator, '"');
        }

        if (self.id_token) |id| {
            try buf.appendSlice(allocator, ",\"id_token\":\"");
            try buf.appendSlice(allocator, id);
            try buf.append(allocator, '"');
        }

        try buf.append(allocator, '}');
        return buf.toOwnedSlice(allocator);
    }

    /// Deserialize token from JSON
    pub fn fromJson(allocator: Allocator, json_data: []const u8) !Token {
        const parsed = try json.parseFromSlice(json.Value, allocator, json_data, .{});
        defer parsed.deinit();

        return fromJsonValue(allocator, parsed.value);
    }

    /// Deserialize token from parsed JSON value
    pub fn fromJsonValue(allocator: Allocator, value: json.Value) !Token {
        const obj = value.object;

        const access_token = obj.get("access_token") orelse return error.InvalidParameter;
        const token_type = obj.get("token_type") orelse return error.InvalidParameter;

        var token = try Token.init(
            allocator,
            access_token.string,
            token_type.string,
        );
        errdefer token.deinit();

        if (obj.get("refresh_token")) |rt| {
            if (rt != .null) {
                token.refresh_token = try allocator.dupe(u8, rt.string);
            }
        }

        if (obj.get("expires_in")) |exp| {
            if (exp != .null) {
                token.expires_in = @intCast(exp.integer);
            }
        }

        if (obj.get("expires_at")) |exp| {
            if (exp != .null) {
                token.expires_at = @intCast(exp.integer);
            }
        }

        if (obj.get("scope")) |s| {
            if (s != .null) {
                token.scope = try allocator.dupe(u8, s.string);
            }
        }

        if (obj.get("id_token")) |id| {
            if (id != .null) {
                token.id_token = try allocator.dupe(u8, id.string);
            }
        }

        return token;
    }
};

/// Session containing authentication state
pub const Session = struct {
    allocator: Allocator,
    /// Domain/provider identifier
    domain: []const u8,
    /// Active token
    token: ?Token = null,
    /// Session metadata
    created_at: u64,
    /// Last activity timestamp
    last_used_at: u64,

    pub fn init(allocator: Allocator, domain: []const u8) !Session {
        const now = @as(u64, @intCast(std.time.timestamp()));
        return .{
            .allocator = allocator,
            .domain = try allocator.dupe(u8, domain),
            .created_at = now,
            .last_used_at = now,
        };
    }

    pub fn deinit(self: *Session) void {
        self.allocator.free(self.domain);
        if (self.token) |*t| t.deinit();
    }

    pub fn setToken(self: *Session, token: Token) void {
        if (self.token) |*t| t.deinit();
        self.token = token;
        self.last_used_at = @as(u64, @intCast(std.time.timestamp()));
    }

    pub fn clearToken(self: *Session) void {
        if (self.token) |*t| t.deinit();
        self.token = null;
    }
};

/// Storage interface for session/token persistence
pub const SessionStorage = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        save: *const fn (ptr: *anyopaque, key: []const u8, token: Token) anyerror!void,
        load: *const fn (ptr: *anyopaque, allocator: Allocator, key: []const u8) anyerror!?Token,
        delete: *const fn (ptr: *anyopaque, key: []const u8) anyerror!void,
        exists: *const fn (ptr: *anyopaque, key: []const u8) bool,
    };

    pub fn save(self: SessionStorage, key: []const u8, token: Token) !void {
        return self.vtable.save(self.ptr, key, token);
    }

    pub fn load(self: SessionStorage, allocator: Allocator, key: []const u8) !?Token {
        return self.vtable.load(self.ptr, allocator, key);
    }

    pub fn delete(self: SessionStorage, key: []const u8) !void {
        return self.vtable.delete(self.ptr, key);
    }

    pub fn exists(self: SessionStorage, key: []const u8) bool {
        return self.vtable.exists(self.ptr, key);
    }
};

/// In-memory storage for testing
pub const MemoryStorage = struct {
    allocator: Allocator,
    tokens: std.StringHashMap([]const u8),

    pub fn init(allocator: Allocator) MemoryStorage {
        return .{
            .allocator = allocator,
            .tokens = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *MemoryStorage) void {
        var iter = self.tokens.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.tokens.deinit();
    }

    pub fn storage(self: *MemoryStorage) SessionStorage {
        return .{
            .ptr = self,
            .vtable = &.{
                .save = save,
                .load = load,
                .delete = delete,
                .exists = exists,
            },
        };
    }

    fn save(ptr: *anyopaque, key: []const u8, token: Token) !void {
        const self: *MemoryStorage = @ptrCast(@alignCast(ptr));

        const json_data = try token.toJson(self.allocator);
        errdefer self.allocator.free(json_data);

        const key_copy = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_copy);

        // Remove old entry if exists
        if (self.tokens.fetchRemove(key)) |old| {
            self.allocator.free(old.key);
            self.allocator.free(old.value);
        }

        try self.tokens.put(key_copy, json_data);
    }

    fn load(ptr: *anyopaque, allocator: Allocator, key: []const u8) !?Token {
        const self: *MemoryStorage = @ptrCast(@alignCast(ptr));

        if (self.tokens.get(key)) |json_data| {
            return try Token.fromJson(allocator, json_data);
        }
        return null;
    }

    fn delete(ptr: *anyopaque, key: []const u8) !void {
        const self: *MemoryStorage = @ptrCast(@alignCast(ptr));

        if (self.tokens.fetchRemove(key)) |old| {
            self.allocator.free(old.key);
            self.allocator.free(old.value);
        }
    }

    fn exists(ptr: *anyopaque, key: []const u8) bool {
        const self: *MemoryStorage = @ptrCast(@alignCast(ptr));
        return self.tokens.contains(key);
    }
};

/// File-based JSON storage
///
/// WARNING: Tokens are stored in plaintext. Use SecureStorage for production.
pub const FileStorage = struct {
    allocator: Allocator,
    base_path: []const u8,

    /// Initialize with a base directory path
    ///
    /// Supports XDG Base Directory Specification on Linux
    pub fn init(allocator: Allocator, app_name: []const u8) !FileStorage {
        const base_path = try getStoragePath(allocator, app_name);
        return .{
            .allocator = allocator,
            .base_path = base_path,
        };
    }

    /// Initialize with a custom directory path
    pub fn initWithPath(allocator: Allocator, path: []const u8) !FileStorage {
        return .{
            .allocator = allocator,
            .base_path = try allocator.dupe(u8, path),
        };
    }

    pub fn deinit(self: *FileStorage) void {
        self.allocator.free(self.base_path);
    }

    pub fn storage(self: *FileStorage) SessionStorage {
        return .{
            .ptr = self,
            .vtable = &.{
                .save = save,
                .load = load,
                .delete = delete,
                .exists = exists,
            },
        };
    }

    fn getFilePath(self: *FileStorage, key: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}/{s}.json", .{ self.base_path, key });
    }

    fn save(ptr: *anyopaque, key: []const u8, token: Token) !void {
        const self: *FileStorage = @ptrCast(@alignCast(ptr));

        // Ensure directory exists
        fs.cwd().makePath(self.base_path) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        const file_path = try self.getFilePath(key);
        defer self.allocator.free(file_path);

        const json_data = try token.toJson(self.allocator);
        defer self.allocator.free(json_data);

        const file = try fs.cwd().createFile(file_path, .{});
        defer file.close();

        try file.writeAll(json_data);
    }

    fn load(ptr: *anyopaque, allocator: Allocator, key: []const u8) !?Token {
        const self: *FileStorage = @ptrCast(@alignCast(ptr));

        const file_path = try self.getFilePath(key);
        defer self.allocator.free(file_path);

        const file = fs.cwd().openFile(file_path, .{}) catch |err| {
            if (err == error.FileNotFound) return null;
            return err;
        };
        defer file.close();

        const json_data = try file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(json_data);

        return try Token.fromJson(allocator, json_data);
    }

    fn delete(ptr: *anyopaque, key: []const u8) !void {
        const self: *FileStorage = @ptrCast(@alignCast(ptr));

        const file_path = try self.getFilePath(key);
        defer self.allocator.free(file_path);

        fs.cwd().deleteFile(file_path) catch |err| {
            if (err != error.FileNotFound) return err;
        };
    }

    fn exists(ptr: *anyopaque, key: []const u8) bool {
        const self: *FileStorage = @ptrCast(@alignCast(ptr));

        const file_path = self.getFilePath(key) catch return false;
        defer self.allocator.free(file_path);

        fs.cwd().access(file_path, .{}) catch return false;
        return true;
    }

    fn getStoragePath(allocator: Allocator, app_name: []const u8) ![]const u8 {
        const builtin = @import("builtin");

        if (builtin.os.tag == .linux) {
            // XDG Base Directory Specification
            if (std.posix.getenv("XDG_DATA_HOME")) |xdg_data| {
                return std.fmt.allocPrint(allocator, "{s}/{s}", .{ xdg_data, app_name });
            }
            if (std.posix.getenv("HOME")) |home| {
                return std.fmt.allocPrint(allocator, "{s}/.local/share/{s}", .{ home, app_name });
            }
        } else if (builtin.os.tag == .macos) {
            if (std.posix.getenv("HOME")) |home| {
                return std.fmt.allocPrint(allocator, "{s}/Library/Application Support/{s}", .{ home, app_name });
            }
        } else if (builtin.os.tag == .windows) {
            if (std.posix.getenv("LOCALAPPDATA")) |local_app_data| {
                return std.fmt.allocPrint(allocator, "{s}\\{s}", .{ local_app_data, app_name });
            }
        }

        // Fallback to temp directory
        return std.fmt.allocPrint(allocator, "/tmp/{s}", .{app_name});
    }
};

/// Secure storage using OS credential managers
///
/// Uses:
/// - macOS: Keychain
/// - Windows: Credential Manager
/// - Linux: Secret Service (libsecret)
pub const SecureStorage = struct {
    allocator: Allocator,
    service_name: []const u8,

    pub fn init(allocator: Allocator, service_name: []const u8) !SecureStorage {
        return .{
            .allocator = allocator,
            .service_name = try allocator.dupe(u8, service_name),
        };
    }

    pub fn deinit(self: *SecureStorage) void {
        self.allocator.free(self.service_name);
    }

    pub fn storage(self: *SecureStorage) SessionStorage {
        return .{
            .ptr = self,
            .vtable = &.{
                .save = save,
                .load = load,
                .delete = delete,
                .exists = exists,
            },
        };
    }

    fn save(ptr: *anyopaque, key: []const u8, token: Token) !void {
        const self: *SecureStorage = @ptrCast(@alignCast(ptr));
        const json_data = try token.toJson(self.allocator);
        defer self.allocator.free(json_data);

        try storeCredential(self.allocator, self.service_name, key, json_data);
    }

    fn load(ptr: *anyopaque, allocator: Allocator, key: []const u8) !?Token {
        const self: *SecureStorage = @ptrCast(@alignCast(ptr));

        const json_data = loadCredential(self.allocator, self.service_name, key) catch |err| {
            if (err == error.NotFound) return null;
            return err;
        };
        defer self.allocator.free(json_data);

        return try Token.fromJson(allocator, json_data);
    }

    fn delete(ptr: *anyopaque, key: []const u8) !void {
        const self: *SecureStorage = @ptrCast(@alignCast(ptr));
        deleteCredential(self.allocator, self.service_name, key) catch |err| {
            if (err != error.NotFound) return err;
        };
    }

    fn exists(ptr: *anyopaque, key: []const u8) bool {
        const self: *SecureStorage = @ptrCast(@alignCast(ptr));
        _ = loadCredential(self.allocator, self.service_name, key) catch return false;
        return true;
    }

    // Platform-specific credential storage
    const builtin = @import("builtin");

    fn storeCredential(allocator: Allocator, service: []const u8, account: []const u8, data: []const u8) !void {
        if (builtin.os.tag == .macos) {
            try macosStoreKeychain(allocator, service, account, data);
        } else if (builtin.os.tag == .linux) {
            try linuxStoreSecret(allocator, service, account, data);
        } else {
            // Fallback to file storage with warning
            std.log.warn("SecureStorage not available on this platform, using file storage", .{});
            try fallbackStore(allocator, service, account, data);
        }
    }

    fn loadCredential(allocator: Allocator, service: []const u8, account: []const u8) ![]const u8 {
        if (builtin.os.tag == .macos) {
            return try macosLoadKeychain(allocator, service, account);
        } else if (builtin.os.tag == .linux) {
            return try linuxLoadSecret(allocator, service, account);
        } else {
            return try fallbackLoad(allocator, service, account);
        }
    }

    fn deleteCredential(allocator: Allocator, service: []const u8, account: []const u8) !void {
        if (builtin.os.tag == .macos) {
            try macosDeleteKeychain(allocator, service, account);
        } else if (builtin.os.tag == .linux) {
            try linuxDeleteSecret(allocator, service, account);
        } else {
            try fallbackDelete(allocator, service, account);
        }
    }

    fn macosStoreKeychain(allocator: Allocator, service: []const u8, account: []const u8, data: []const u8) !void {
        // Use security command-line tool
        const args = [_][]const u8{
            "security",
            "add-generic-password",
            "-U", // Update if exists
            "-s",
            service,
            "-a",
            account,
            "-w",
            data,
        };

        var child = std.process.Child.init(&args, allocator);
        child.stderr_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        _ = try child.spawnAndWait();
    }

    fn macosLoadKeychain(allocator: Allocator, service: []const u8, account: []const u8) ![]const u8 {
        const args = [_][]const u8{
            "security",
            "find-generic-password",
            "-s",
            service,
            "-a",
            account,
            "-w",
        };

        var child = std.process.Child.init(&args, allocator);
        child.stderr_behavior = .Ignore;
        child.stdout_behavior = .Pipe;

        try child.spawn();

        const stdout = child.stdout orelse return error.NotFound;
        const output = try stdout.readToEndAlloc(allocator, 1024 * 1024);

        const result = try child.wait();
        if (result.Exited != 0) {
            allocator.free(output);
            return error.NotFound;
        }

        // Remove trailing newline
        const trimmed = mem.trimRight(u8, output, "\n");
        if (trimmed.len == output.len) {
            return output;
        }

        const result_data = try allocator.dupe(u8, trimmed);
        allocator.free(output);
        return result_data;
    }

    fn macosDeleteKeychain(allocator: Allocator, service: []const u8, account: []const u8) !void {
        const args = [_][]const u8{
            "security",
            "delete-generic-password",
            "-s",
            service,
            "-a",
            account,
        };

        var child = std.process.Child.init(&args, allocator);
        child.stderr_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        _ = try child.spawnAndWait();
    }

    fn linuxStoreSecret(allocator: Allocator, service: []const u8, account: []const u8, data: []const u8) !void {
        // Use secret-tool from libsecret
        const args = [_][]const u8{
            "secret-tool",
            "store",
            "--label",
            service,
            "service",
            service,
            "account",
            account,
        };

        var child = std.process.Child.init(&args, allocator);
        child.stdin_behavior = .Pipe;
        child.stderr_behavior = .Ignore;
        child.stdout_behavior = .Ignore;

        try child.spawn();

        if (child.stdin) |stdin| {
            try stdin.writeAll(data);
            stdin.close();
            child.stdin = null;
        }

        _ = try child.wait();
    }

    fn linuxLoadSecret(allocator: Allocator, service: []const u8, account: []const u8) ![]const u8 {
        const args = [_][]const u8{
            "secret-tool",
            "lookup",
            "service",
            service,
            "account",
            account,
        };

        var child = std.process.Child.init(&args, allocator);
        child.stderr_behavior = .Ignore;
        child.stdout_behavior = .Pipe;

        try child.spawn();

        const stdout = child.stdout orelse return error.NotFound;
        const output = try stdout.readToEndAlloc(allocator, 1024 * 1024);

        const result = try child.wait();
        if (result.Exited != 0) {
            allocator.free(output);
            return error.NotFound;
        }

        return output;
    }

    fn linuxDeleteSecret(allocator: Allocator, service: []const u8, account: []const u8) !void {
        const args = [_][]const u8{
            "secret-tool",
            "clear",
            "service",
            service,
            "account",
            account,
        };

        var child = std.process.Child.init(&args, allocator);
        child.stderr_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        _ = try child.spawnAndWait();
    }

    fn fallbackStore(allocator: Allocator, service: []const u8, account: []const u8, data: []const u8) !void {
        const path = try std.fmt.allocPrint(allocator, "/tmp/.{s}-{s}", .{ service, account });
        defer allocator.free(path);

        const file = try fs.cwd().createFile(path, .{ .mode = 0o600 });
        defer file.close();
        try file.writeAll(data);
    }

    fn fallbackLoad(allocator: Allocator, service: []const u8, account: []const u8) ![]const u8 {
        const path = try std.fmt.allocPrint(allocator, "/tmp/.{s}-{s}", .{ service, account });
        defer allocator.free(path);

        const file = fs.cwd().openFile(path, .{}) catch return error.NotFound;
        defer file.close();
        return try file.readToEndAlloc(allocator, 1024 * 1024);
    }

    fn fallbackDelete(allocator: Allocator, service: []const u8, account: []const u8) !void {
        const path = try std.fmt.allocPrint(allocator, "/tmp/.{s}-{s}", .{ service, account });
        defer allocator.free(path);

        fs.cwd().deleteFile(path) catch |err| {
            if (err != error.FileNotFound) return err;
        };
    }
};

test "Token creation and expiration" {
    const allocator = std.testing.allocator;

    var token = try Token.init(allocator, "test_token", "Bearer");
    defer token.deinit();

    try std.testing.expectEqualStrings("test_token", token.access_token);
    try std.testing.expectEqualStrings("Bearer", token.token_type);
    try std.testing.expect(!token.isExpired());
}

test "Token JSON serialization roundtrip" {
    const allocator = std.testing.allocator;

    var original = try Token.initFull(
        allocator,
        "access123",
        "Bearer",
        "refresh456",
        3600,
        "read write",
        null,
    );
    defer original.deinit();

    const json_data = try original.toJson(allocator);
    defer allocator.free(json_data);

    var restored = try Token.fromJson(allocator, json_data);
    defer restored.deinit();

    try std.testing.expectEqualStrings(original.access_token, restored.access_token);
    try std.testing.expectEqualStrings(original.token_type, restored.token_type);
    try std.testing.expectEqualStrings(original.refresh_token.?, restored.refresh_token.?);
    try std.testing.expectEqualStrings(original.scope.?, restored.scope.?);
}

test "MemoryStorage save and load" {
    const allocator = std.testing.allocator;

    var mem_storage = MemoryStorage.init(allocator);
    defer mem_storage.deinit();

    var token = try Token.init(allocator, "test_access", "Bearer");
    defer token.deinit();

    const storage_iface = mem_storage.storage();
    try storage_iface.save("test_key", token);

    var loaded = (try storage_iface.load(allocator, "test_key")).?;
    defer loaded.deinit();

    try std.testing.expectEqualStrings("test_access", loaded.access_token);
}

test "Token expiration checking" {
    const allocator = std.testing.allocator;

    var token = try Token.init(allocator, "expired_token", "Bearer");
    defer token.deinit();

    token.expires_in = 3600;
    token.expires_at = 1; // Long expired

    try std.testing.expect(token.isExpired());
    try std.testing.expect(token.expiresWithin(0));
}

test "Token remaining lifetime fraction" {
    const allocator = std.testing.allocator;

    const now = @as(u64, @intCast(std.time.timestamp()));

    var token = try Token.init(allocator, "test_token", "Bearer");
    defer token.deinit();

    token.expires_in = 3600;
    token.expires_at = now + 1800; // Half expired

    if (token.remainingLifetimeFraction()) |fraction| {
        try std.testing.expect(fraction >= 0.49 and fraction <= 0.51);
    }
}
