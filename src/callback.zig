//! Local HTTP callback server for OAuth redirects
//!
//! This module provides a simple HTTP server that listens for OAuth
//! authorization code callbacks. It handles the redirect from the
//! authorization server and extracts the authorization code.
//!
//! ## Example
//!
//! ```zig
//! var server = try CallbackServer.init(allocator, 0); // Random port
//! defer server.deinit();
//!
//! const port = server.getPort();
//! // Redirect user to authorization URL with redirect_uri=http://127.0.0.1:{port}/callback
//!
//! const result = try server.waitForCallback(60); // 60 second timeout
//! defer result.deinit();
//!
//! if (result.code) |code| {
//!     // Exchange code for token
//! }
//! ```

const std = @import("std");
const net = std.net;
const http = std.http;
const Allocator = std.mem.Allocator;

/// Cross-platform helper to check if an environment variable is set
fn hasEnvVar(name: []const u8) bool {
    if (std.process.getEnvVarOwned(std.heap.page_allocator, name)) |val| {
        std.heap.page_allocator.free(val);
        return true;
    } else |_| {
        return false;
    }
}

/// Result of OAuth callback
pub const CallbackResult = struct {
    allocator: Allocator,
    /// Authorization code received from the server
    code: ?[]const u8,
    /// State parameter for CSRF verification
    state: ?[]const u8,
    /// Error code if authorization failed
    error_code: ?[]const u8,
    /// Error description
    error_description: ?[]const u8,

    pub fn init(allocator: Allocator) CallbackResult {
        return .{
            .allocator = allocator,
            .code = null,
            .state = null,
            .error_code = null,
            .error_description = null,
        };
    }

    pub fn deinit(self: *CallbackResult) void {
        if (self.code) |c| self.allocator.free(c);
        if (self.state) |s| self.allocator.free(s);
        if (self.error_code) |e| self.allocator.free(e);
        if (self.error_description) |d| self.allocator.free(d);
    }

    /// Check if the callback was successful
    pub fn isSuccess(self: *const CallbackResult) bool {
        return self.code != null and self.error_code == null;
    }

    /// Check if there was an error
    pub fn isError(self: *const CallbackResult) bool {
        return self.error_code != null;
    }
};

/// Local HTTP server for OAuth callbacks
pub const CallbackServer = struct {
    allocator: Allocator,
    server: net.Server,
    port: u16,

    /// HTML response for successful authorization
    const success_html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\    <title>Authorization Successful</title>
        \\    <style>
        \\        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif;
        \\               display: flex; justify-content: center; align-items: center;
        \\               height: 100vh; margin: 0; background: #f5f5f5; }
        \\        .container { text-align: center; padding: 40px; background: white;
        \\                     border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        \\        h1 { color: #22c55e; margin-bottom: 16px; }
        \\        p { color: #666; }
        \\    </style>
        \\</head>
        \\<body>
        \\    <div class="container">
        \\        <h1>Authorization Successful</h1>
        \\        <p>You can close this window and return to the application.</p>
        \\    </div>
        \\</body>
        \\</html>
    ;

    /// HTML response for failed authorization
    const error_html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\    <title>Authorization Failed</title>
        \\    <style>
        \\        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif;
        \\               display: flex; justify-content: center; align-items: center;
        \\               height: 100vh; margin: 0; background: #f5f5f5; }
        \\        .container { text-align: center; padding: 40px; background: white;
        \\                     border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        \\        h1 { color: #ef4444; margin-bottom: 16px; }
        \\        p { color: #666; }
        \\    </style>
        \\</head>
        \\<body>
        \\    <div class="container">
        \\        <h1>Authorization Failed</h1>
        \\        <p>An error occurred during authorization. Please try again.</p>
        \\    </div>
        \\</body>
        \\</html>
    ;

    /// Initialize a callback server on the specified port
    ///
    /// Use port 0 to let the OS assign a random available port
    pub fn init(allocator: Allocator, port: u16) !CallbackServer {
        const address = net.Address.initIp4(.{ 127, 0, 0, 1 }, port);
        const server = try address.listen(.{
            .reuse_address = true,
        });

        const actual_port = server.listen_address.getPort();

        return .{
            .allocator = allocator,
            .server = server,
            .port = actual_port,
        };
    }

    pub fn deinit(self: *CallbackServer) void {
        self.server.deinit();
    }

    /// Get the port the server is listening on
    pub fn getPort(self: *const CallbackServer) u16 {
        return self.port;
    }

    /// Get the full callback URL
    pub fn getCallbackUrl(self: *const CallbackServer, allocator: Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}/callback", .{self.port});
    }

    /// Wait for an OAuth callback
    ///
    /// Blocks until a callback is received or the timeout expires.
    /// timeout_seconds: Maximum time to wait (0 = no timeout)
    pub fn waitForCallback(self: *CallbackServer, timeout_seconds: u32) !CallbackResult {
        var result = CallbackResult.init(self.allocator);
        errdefer result.deinit();

        // Set socket timeout if specified
        if (timeout_seconds > 0) {
            const timeout: std.posix.timeval = .{
                .sec = @intCast(timeout_seconds),
                .usec = 0,
            };
            try std.posix.setsockopt(
                self.server.stream.handle,
                std.posix.SOL.SOCKET,
                std.posix.SO.RCVTIMEO,
                std.mem.asBytes(&timeout),
            );
        }

        // Accept connection
        var connection = self.server.accept() catch |err| {
            if (err == error.WouldBlock) {
                return error.Timeout;
            }
            return err;
        };
        defer connection.stream.close();

        // Read the HTTP request
        var buf: [4096]u8 = undefined;
        const bytes_read = try connection.stream.read(&buf);
        if (bytes_read == 0) {
            return error.ConnectionClosed;
        }

        const request = buf[0..bytes_read];

        // Parse the request line to get the path
        const path = try parsePath(request);

        // Parse query parameters
        if (std.mem.indexOf(u8, path, "?")) |query_start| {
            const query_string = path[query_start + 1 ..];
            try parseQueryParams(self.allocator, query_string, &result);
        }

        // Send appropriate response
        const response_html = if (result.isSuccess()) success_html else error_html;
        const status = if (result.isSuccess()) "200 OK" else "400 Bad Request";

        var response_buf: [2048]u8 = undefined;
        const response = try std.fmt.bufPrint(&response_buf,
            \\HTTP/1.1 {s}
            \\Content-Type: text/html
            \\Content-Length: {d}
            \\Connection: close
            \\
            \\{s}
        , .{ status, response_html.len, response_html });

        _ = try connection.stream.write(response);

        return result;
    }

    fn parsePath(request: []const u8) ![]const u8 {
        // Find the first line (request line)
        const line_end = std.mem.indexOf(u8, request, "\r\n") orelse request.len;
        const request_line = request[0..line_end];

        // Parse "GET /path HTTP/1.1"
        var parts = std.mem.splitScalar(u8, request_line, ' ');
        _ = parts.next(); // Skip method (GET)
        const path = parts.next() orelse return error.InvalidRequest;

        return path;
    }

    fn parseQueryParams(allocator: Allocator, query: []const u8, result: *CallbackResult) !void {
        var params = std.mem.splitScalar(u8, query, '&');
        while (params.next()) |param| {
            if (std.mem.indexOf(u8, param, "=")) |eq_pos| {
                const key = param[0..eq_pos];
                const value = param[eq_pos + 1 ..];

                const decoded = try urlDecode(allocator, value);

                if (std.mem.eql(u8, key, "code")) {
                    result.code = decoded;
                } else if (std.mem.eql(u8, key, "state")) {
                    result.state = decoded;
                } else if (std.mem.eql(u8, key, "error")) {
                    result.error_code = decoded;
                } else if (std.mem.eql(u8, key, "error_description")) {
                    result.error_description = decoded;
                } else {
                    allocator.free(decoded);
                }
            }
        }
    }

    fn urlDecode(allocator: Allocator, input: []const u8) ![]const u8 {
        var output: std.ArrayListUnmanaged(u8) = .{};
        errdefer output.deinit(allocator);

        var i: usize = 0;
        while (i < input.len) {
            if (input[i] == '%' and i + 2 < input.len) {
                const hex = input[i + 1 .. i + 3];
                const byte = std.fmt.parseInt(u8, hex, 16) catch {
                    try output.append(allocator, input[i]);
                    i += 1;
                    continue;
                };
                try output.append(allocator, byte);
                i += 3;
            } else if (input[i] == '+') {
                try output.append(allocator, ' ');
                i += 1;
            } else {
                try output.append(allocator, input[i]);
                i += 1;
            }
        }

        return output.toOwnedSlice(allocator);
    }
};

/// Build an authorization URL with the given parameters
pub fn buildAuthorizationUrl(
    allocator: Allocator,
    authorization_endpoint: []const u8,
    client_id: []const u8,
    redirect_uri: []const u8,
    scope: ?[]const u8,
    state: []const u8,
    code_challenge: []const u8,
) ![]const u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(allocator);

    try buf.appendSlice(allocator, authorization_endpoint);
    try buf.append(allocator, '?');
    try buf.appendSlice(allocator, "response_type=code");
    try buf.appendSlice(allocator, "&client_id=");
    try appendUrlEncoded(allocator, &buf, client_id);
    try buf.appendSlice(allocator, "&redirect_uri=");
    try appendUrlEncoded(allocator, &buf, redirect_uri);
    try buf.appendSlice(allocator, "&state=");
    try appendUrlEncoded(allocator, &buf, state);
    try buf.appendSlice(allocator, "&code_challenge=");
    try appendUrlEncoded(allocator, &buf, code_challenge);
    try buf.appendSlice(allocator, "&code_challenge_method=S256");

    if (scope) |s| {
        try buf.appendSlice(allocator, "&scope=");
        try appendUrlEncoded(allocator, &buf, s);
    }

    return buf.toOwnedSlice(allocator);
}

/// Append a URL-encoded string to the buffer (RFC 3986 unreserved characters)
///
/// This function encodes all characters except unreserved characters:
/// - Alphanumeric: A-Z, a-z, 0-9
/// - Special: - _ . ~
///
/// All other characters are percent-encoded as %XX where XX is the hex value.
pub fn appendUrlEncoded(allocator: Allocator, buf: *std.ArrayListUnmanaged(u8), input: []const u8) !void {
    for (input) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
            try buf.append(allocator, c);
        } else {
            try buf.append(allocator, '%');
            const hex = "0123456789ABCDEF";
            try buf.append(allocator, hex[c >> 4]);
            try buf.append(allocator, hex[c & 0x0F]);
        }
    }
}

/// Open a URL in the system's default browser
///
/// Note: This function validates that the URL is safe before passing to system commands.
/// Only HTTP/HTTPS URLs are allowed to prevent command injection.
pub fn openBrowser(url: []const u8) !void {
    const builtin = @import("builtin");

    // Check for SCHLUSSEL_NO_BROWSER environment variable
    if (hasEnvVar("SCHLUSSEL_NO_BROWSER")) {
        return; // Don't open browser
    }

    // Validate URL to prevent command injection
    // Only allow http:// and https:// URLs
    if (!std.mem.startsWith(u8, url, "http://") and !std.mem.startsWith(u8, url, "https://")) {
        return error.InvalidUrl;
    }

    // Check for dangerous characters that could be interpreted as shell commands
    for (url) |c| {
        switch (c) {
            // Disallow shell metacharacters
            '&', '|', ';', '`', '$', '(', ')', '{', '}', '[', ']', '<', '>', '\n', '\r', 0 => {
                return error.InvalidUrl;
            },
            else => {},
        }
    }

    const allocator = std.heap.page_allocator;

    if (builtin.os.tag == .macos) {
        var child = std.process.Child.init(&.{ "open", url }, allocator);
        child.stderr_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        _ = try child.spawnAndWait();
    } else if (builtin.os.tag == .linux) {
        var child = std.process.Child.init(&.{ "xdg-open", url }, allocator);
        child.stderr_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        _ = try child.spawnAndWait();
    } else if (builtin.os.tag == .windows) {
        // On Windows, use 'start' via cmd.exe
        // The URL has been validated above to not contain dangerous characters
        var child = std.process.Child.init(&.{ "cmd", "/c", "start", "", url }, allocator);
        child.stderr_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        _ = try child.spawnAndWait();
    }
}

test "CallbackResult initialization" {
    const allocator = std.testing.allocator;

    var result = CallbackResult.init(allocator);
    defer result.deinit();

    try std.testing.expect(!result.isSuccess());
    try std.testing.expect(!result.isError());
}

test "CallbackResult success check" {
    const allocator = std.testing.allocator;

    var result = CallbackResult.init(allocator);
    result.code = try allocator.dupe(u8, "test_code");
    defer result.deinit();

    try std.testing.expect(result.isSuccess());
    try std.testing.expect(!result.isError());
}

test "CallbackResult error check" {
    const allocator = std.testing.allocator;

    var result = CallbackResult.init(allocator);
    result.error_code = try allocator.dupe(u8, "access_denied");
    defer result.deinit();

    try std.testing.expect(!result.isSuccess());
    try std.testing.expect(result.isError());
}

test "buildAuthorizationUrl" {
    const allocator = std.testing.allocator;

    const url = try buildAuthorizationUrl(
        allocator,
        "https://example.com/authorize",
        "client123",
        "http://localhost:8080/callback",
        "read write",
        "state123",
        "challenge123",
    );
    defer allocator.free(url);

    try std.testing.expect(std.mem.indexOf(u8, url, "https://example.com/authorize?") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "response_type=code") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "client_id=client123") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "code_challenge=challenge123") != null);
    try std.testing.expect(std.mem.indexOf(u8, url, "code_challenge_method=S256") != null);
}

test "URL encoding special characters" {
    const allocator = std.testing.allocator;

    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(allocator);

    try appendUrlEncoded(allocator, &buf, "hello world");
    try std.testing.expectEqualStrings("hello%20world", buf.items);
}
