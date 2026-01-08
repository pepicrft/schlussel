//! GitHub Device Flow Example
//!
//! This example demonstrates how to authenticate with GitHub using the
//! Device Code Flow (RFC 8628). This is the recommended authentication
//! method for CLI applications.
//!
//! ## Prerequisites
//!
//! 1. Create a GitHub OAuth App at https://github.com/settings/applications/new
//! 2. Enable "Device Authorization Flow" in the app settings
//! 3. Set the GITHUB_CLIENT_ID environment variable
//!
//! ## Running
//!
//! ```bash
//! export GITHUB_CLIENT_ID="your-client-id"
//! zig build example-github-device
//! ./zig-out/bin/github_device_flow
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
    var stderr_writer = std.fs.File.stderr().writer(&.{});
    const stderr = &stderr_writer.interface;

    // Get client ID from environment
    const client_id = std.posix.getenv("GITHUB_CLIENT_ID") orelse {
        try stderr.print("Error: GITHUB_CLIENT_ID environment variable not set\n", .{});
        try stderr.print("\nTo use this example:\n", .{});
        try stderr.print("1. Create a GitHub OAuth App at https://github.com/settings/applications/new\n", .{});
        try stderr.print("2. Enable 'Device Authorization Flow' in the app settings\n", .{});
        try stderr.print("3. Run: export GITHUB_CLIENT_ID=\"your-client-id\"\n", .{});
        return;
    };

    // Create OAuth configuration for GitHub
    const config = schlussel.OAuthConfig.github(client_id, "repo user");

    // Create in-memory storage (for demo purposes)
    // In production, use FileStorage or SecureStorage for persistence
    var storage = schlussel.MemoryStorage.init(allocator);
    defer storage.deinit();

    // Create OAuth client
    var client = schlussel.OAuthClient.init(allocator, config, storage.storage());
    defer client.deinit();

    try stdout.print("\n=== GitHub Device Flow Example ===\n\n", .{});
    try stdout.print("Starting Device Code Flow authorization...\n", .{});

    // Perform Device Code Flow
    // This will:
    // 1. Request a device code from GitHub
    // 2. Display the verification URL and user code
    // 3. Open the browser (if SCHLUSSEL_NO_BROWSER is not set)
    // 4. Poll until the user completes authorization
    var token = client.authorizeDevice() catch |err| {
        try stderr.print("\nAuthorization failed: {s}\n", .{@errorName(err)});
        return;
    };
    defer token.deinit();

    try stdout.print("\n=== Authorization Successful! ===\n\n", .{});
    try stdout.print("Token type: {s}\n", .{token.token_type});
    try stdout.print("Access token: {s}...{s}\n", .{
        token.access_token[0..@min(8, token.access_token.len)],
        token.access_token[@max(0, token.access_token.len -| 4)..],
    });

    if (token.scope) |scope| {
        try stdout.print("Scope: {s}\n", .{scope});
    }

    if (token.expires_at) |expires_at| {
        try stdout.print("Expires at: {d} (Unix timestamp)\n", .{expires_at});
    }

    // Save token for later use
    try client.saveToken("github_token", token);
    try stdout.print("\nToken saved to storage with key 'github_token'\n", .{});

    // Demonstrate retrieving the token
    if (try client.getToken("github_token")) |retrieved| {
        var mutable_retrieved = retrieved;
        defer mutable_retrieved.deinit();
        try stdout.print("Token retrieved successfully from storage\n", .{});
    }

    try stdout.print("\n=== Example Complete ===\n", .{});
}
