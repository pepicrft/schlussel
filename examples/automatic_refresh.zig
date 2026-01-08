//! Automatic Token Refresh Example
//!
//! This example demonstrates automatic token refresh functionality:
//! - Basic token expiration checking
//! - Automatic refresh when token is expired
//! - Proactive refresh with configurable thresholds
//!
//! ## Running
//!
//! ```bash
//! zig build example-auto-refresh
//! ./zig-out/bin/automatic_refresh
//! ```

const std = @import("std");
const schlussel = @import("schlussel");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Use unbuffered output for simplicity
    var stdout_writer = std.fs.File.stdout().writer(&.{});
    const stdout = &stdout_writer.interface;

    try stdout.print("\n=== Automatic Token Refresh Example ===\n\n", .{});

    // Create mock storage and client for demonstration
    var storage = schlussel.MemoryStorage.init(allocator);
    defer storage.deinit();

    const config = schlussel.OAuthConfig{
        .client_id = "demo-client",
        .authorization_endpoint = "https://example.com/oauth/authorize",
        .token_endpoint = "https://example.com/oauth/token",
        .redirect_uri = "http://127.0.0.1/callback",
        .scope = "read write",
        .device_authorization_endpoint = null,
    };

    var client = schlussel.OAuthClient.init(allocator, config, storage.storage());
    defer client.deinit();

    // Scenario 1: Valid token (not expired)
    try stdout.print("--- Scenario 1: Valid Token ---\n", .{});
    {
        const now = @as(u64, @intCast(std.time.timestamp()));
        var token = try schlussel.Token.init(allocator, "valid_access_token", "Bearer");
        token.expires_in = 3600;
        token.expires_at = now + 3600; // Expires in 1 hour

        try stdout.print("Token expires in: 3600 seconds\n", .{});
        try stdout.print("Is expired: {}\n", .{token.isExpired()});

        if (token.remainingLifetimeFraction()) |fraction| {
            try stdout.print("Remaining lifetime: {d:.1}%\n", .{fraction * 100});
        }

        token.deinit();
    }

    try stdout.print("\n--- Scenario 2: Nearly Expired Token ---\n", .{});
    {
        const now = @as(u64, @intCast(std.time.timestamp()));
        var token = try schlussel.Token.init(allocator, "nearly_expired_token", "Bearer");
        token.expires_in = 3600;
        token.expires_at = now + 300; // Expires in 5 minutes

        try stdout.print("Token expires in: 300 seconds\n", .{});
        try stdout.print("Is expired: {}\n", .{token.isExpired()});
        try stdout.print("Expires within 10 minutes: {}\n", .{token.expiresWithin(600)});

        if (token.remainingLifetimeFraction()) |fraction| {
            try stdout.print("Remaining lifetime: {d:.1}%\n", .{fraction * 100});
        }

        token.deinit();
    }

    try stdout.print("\n--- Scenario 3: Expired Token ---\n", .{});
    {
        var token = try schlussel.Token.init(allocator, "expired_token", "Bearer");
        token.expires_in = 3600;
        token.expires_at = 1; // Already expired

        try stdout.print("Token expires_at: 1 (long ago)\n", .{});
        try stdout.print("Is expired: {}\n", .{token.isExpired()});

        if (token.remainingLifetimeFraction()) |fraction| {
            try stdout.print("Remaining lifetime: {d:.1}%\n", .{fraction * 100});
        } else {
            try stdout.print("Remaining lifetime: 0% (expired)\n", .{});
        }

        token.deinit();
    }

    try stdout.print("\n--- Token Refresher with Thresholds ---\n", .{});
    {
        try stdout.print("\nThe TokenRefresher provides automatic token refresh:\n", .{});
        try stdout.print("- getValidToken(): Refreshes only when expired\n", .{});
        try stdout.print("- getValidTokenWithThreshold(0.8): Refreshes at 80%% lifetime\n", .{});
        try stdout.print("- getValidTokenWithThreshold(0.5): Refreshes at 50%% lifetime\n", .{});
        try stdout.print("\nProactive refresh reduces authentication failures by\n", .{});
        try stdout.print("refreshing tokens before they expire.\n", .{});
    }

    try stdout.print("\n--- Cross-Process Safety ---\n", .{});
    {
        try stdout.print("\nTokenRefresher.withFileLocking() provides:\n", .{});
        try stdout.print("- File-based locks for cross-process coordination\n", .{});
        try stdout.print("- Check-then-refresh pattern to avoid redundant refreshes\n", .{});
        try stdout.print("- RAII-style lock management (automatic release)\n", .{});
    }

    try stdout.print("\n=== Example Complete ===\n", .{});
}
