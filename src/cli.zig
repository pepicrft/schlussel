//! Command-line interface for Schlussel OAuth operations
//!
//! ## Usage
//!
//! ```bash
//! # Device Code Flow with preset provider
//! schlussel auth device github --client-id <id> --scope "repo user"
//!
//! # Device Code Flow with custom provider
//! schlussel auth device --custom-provider \
//!   --device-code-endpoint https://auth.example.com/oauth/device/code \
//!   --token-endpoint https://auth.example.com/oauth/token \
//!   --client-id <id> \
//!   --scope "read write"
//!
//! # Token management
//! schlussel token get --key github_token
//! schlussel token list
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const oauth = @import("oauth.zig");
const session = @import("session.zig");

const Command = enum {
    device,
    code,
    token,
    help,

    pub fn fromString(str: []const u8) ?Command {
        const eql = std.mem.eql;
        if (eql(u8, str, "device")) return .device;
        if (eql(u8, str, "code")) return .code;
        if (eql(u8, str, "token")) return .token;
        if (eql(u8, str, "help")) return .help;
        return null;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stdout_writer = std.fs.File.stdout().writer(&.{});
    const stdout = &stdout_writer.interface;
    var stderr_writer = std.fs.File.stderr().writer(&.{});
    const stderr = &stderr_writer.interface;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage(stderr);
        return;
    }

    // Parse command
    const command = Command.fromString(args[1]) orelse {
        try stderr.print("Error: Unknown command '{s}'\n\n", .{args[1]});
        try printUsage(stderr);
        return error.UnknownCommand;
    };

    if (command == .help) {
        try printUsage(stdout);
        return;
    }

    // Execute command
    switch (command) {
        .device => try cmdDevice(allocator, args, stdout, stderr),
        .code => try cmdCode(allocator, args, stdout, stderr),
        .token => try cmdToken(allocator, args, stdout, stderr),
        .help => {}, // already handled
    }
}

fn printUsage(writer: anytype) !void {
    try writer.writeAll(
        \\Schlussel OAuth 2.0 Command-Line Tool
        \\
        \\USAGE:
        \\    schlussel <command> [options]
        \\
        \\COMMANDS:
        \\    device              Device Code Flow authentication
        \\    code                Authorization Code Flow with PKCE
        \\    token <action>      Token management operations
        \\    help                Show this help message
        \\
        \\TOKEN ACTIONS:
        \\    get                 Retrieve a stored token
        \\    list                List all stored tokens
        \\    delete              Delete a stored token
        \\
        \\EXAMPLES:
        \\    # Device Code Flow with GitHub
        \\    schlussel device github --client-id <id> --scope "repo user"
        \\
        \\    # Device Code Flow with custom provider
        \\    schlussel device --custom-provider \
        \\      --device-code-endpoint https://auth.example.com/oauth/device/code \
        \\      --token-endpoint https://auth.example.com/oauth/token \
        \\      --client-id <id> \
        \\      --scope "read write"
        \\
        \\    # Get stored token
        \\    schlussel token get --key github_token
        \\
        \\For more help, visit: https://github.com/pepicrft/schlussel
        \\
    );
}

fn cmdDevice(allocator: Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !void {
    if (args.len < 3) {
        try stderr.print("Error: Missing provider name or --custom-provider flag\n\n", .{});
        try stderr.print("USAGE:\n    schlussel device <provider|--custom-provider> [options]\n\n", .{});
        try stderr.print("PROVIDERS:\n    github, google, microsoft, gitlab, tuist\n\n", .{});
        try stderr.print("OPTIONS:\n", .{});
        try stderr.print("    --client-id <id>              OAuth client ID (required)\n", .{});
        try stderr.print("    --client-secret <secret>      OAuth client secret (optional)\n", .{});
        try stderr.print("    --scope <scopes>              OAuth scopes (space-separated)\n", .{});
        try stderr.print("\n", .{});
        try stderr.print("CUSTOM PROVIDER OPTIONS:\n", .{});
        try stderr.print("    --device-code-endpoint <url>  Device authorization endpoint\n", .{});
        try stderr.print("    --token-endpoint <url>        Token endpoint\n", .{});
        try stderr.print("    --authorization-endpoint <url> Authorization endpoint (optional)\n", .{});
        try stderr.print("    --redirect-uri <uri>         Redirect URI (default: http://127.0.0.1/callback)\n", .{});
        return error.MissingArguments;
    }

    // args[0] = program name, args[1] = "device", args[2] = provider or --custom-provider
    const provider_arg = args[2];
    const is_custom = std.mem.eql(u8, provider_arg, "--custom-provider");

    var config: ?oauth.OAuthConfig = null;

    if (is_custom) {
        // Parse custom provider options
        var device_code_endpoint: ?[]const u8 = null;
        var token_endpoint: ?[]const u8 = null;
        var client_id: ?[]const u8 = null;
        var client_secret: ?[]const u8 = null;
        var scope: ?[]const u8 = "read";
        var authorization_endpoint: ?[]const u8 = null;
        var redirect_uri: ?[]const u8 = "http://127.0.0.1/callback";

        var i: usize = 3;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            if (i + 1 >= args.len) {
                try stderr.print("Error: Missing value for option '{s}'\n", .{arg});
                return error.MissingOptionValue;
            }

            if (std.mem.eql(u8, arg, "--device-code-endpoint")) {
                device_code_endpoint = args[i + 1];
                i += 1;
            } else if (std.mem.eql(u8, arg, "--token-endpoint")) {
                token_endpoint = args[i + 1];
                i += 1;
            } else if (std.mem.eql(u8, arg, "--authorization-endpoint")) {
                authorization_endpoint = args[i + 1];
                i += 1;
            } else if (std.mem.eql(u8, arg, "--redirect-uri")) {
                redirect_uri = args[i + 1];
                i += 1;
            } else if (std.mem.eql(u8, arg, "--client-id")) {
                client_id = args[i + 1];
                i += 1;
            } else if (std.mem.eql(u8, arg, "--client-secret")) {
                client_secret = args[i + 1];
                i += 1;
            } else if (std.mem.eql(u8, arg, "--scope")) {
                scope = args[i + 1];
                i += 1;
            } else {
                try stderr.print("Error: Unknown option '{s}'\n", .{arg});
                return error.UnknownOption;
            }
        }

        if (device_code_endpoint == null or token_endpoint == null or client_id == null) {
            try stderr.print("Error: Custom provider requires --device-code-endpoint, --token-endpoint, and --client-id\n", .{});
            return error.MissingRequiredOptions;
        }

        // Create owned config with allocator
        var owned_config = oauth.OAuthConfigOwned{
            .allocator = allocator,
            .client_id = try allocator.dupe(u8, client_id.?),
            .client_secret = if (client_secret) |s| try allocator.dupe(u8, s) else null,
            .authorization_endpoint = try allocator.dupe(u8, authorization_endpoint orelse "https://example.com/oauth/authorize"),
            .token_endpoint = try allocator.dupe(u8, token_endpoint.?),
            .redirect_uri = try allocator.dupe(u8, redirect_uri.?),
            .scope = if (scope) |s| try allocator.dupe(u8, s) else null,
            .device_authorization_endpoint = if (device_code_endpoint) |e| try allocator.dupe(u8, e) else null,
        };
        defer owned_config.deinit();

        config = owned_config.toConfig();
    } else {
        // Use preset provider
        var client_id: ?[]const u8 = null;
        var scope: ?[]const u8 = "repo user";

        var i: usize = 3;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            if (i + 1 >= args.len) {
                try stderr.print("Error: Missing value for option '{s}'\n", .{arg});
                return error.MissingOptionValue;
            }

            if (std.mem.eql(u8, arg, "--client-id")) {
                client_id = args[i + 1];
                i += 1;
            } else if (std.mem.eql(u8, arg, "--scope")) {
                scope = args[i + 1];
                i += 1;
            } else {
                try stderr.print("Error: Unknown option '{s}'\n", .{arg});
                return error.UnknownOption;
            }
        }

        if (client_id == null) {
            try stderr.print("Error: --client-id is required\n", .{});
            return error.MissingRequiredOptions;
        }

        // Create config based on provider name
        config = try createPresetConfig(provider_arg, client_id.?, scope.?);
    }

    // Create storage (default to file storage)
    var storage = try session.FileStorage.init(allocator, "schlussel");
    defer storage.deinit();

    // Create OAuth client
    var client = oauth.OAuthClient.init(allocator, config.?, storage.storage());
    defer client.deinit();

    try stdout.print("\n=== Device Code Flow Authentication ===\n\n", .{});
    try stdout.print("Starting authorization...\n", .{});

    // Perform Device Code Flow
    var token = client.authorizeDevice() catch |err| {
        try stderr.print("\nAuthorization failed: {s}\n", .{@errorName(err)});
        return err;
    };
    defer token.deinit();

    try stdout.print("\n=== Authorization Successful! ===\n\n", .{});
    try stdout.print("Token type: {s}\n", .{token.token_type});

    if (token.scope) |s| {
        try stdout.print("Scope: {s}\n", .{s});
    }

    if (token.expires_at) |expires_at| {
        try stdout.print("Expires at: {d} (Unix timestamp)\n", .{expires_at});
    }

    // Save token
    const storage_key = if (is_custom) "custom_token" else provider_arg;
    try client.saveToken(storage_key, token);
    try stdout.print("\nToken saved with key: {s}\n", .{storage_key});
}

fn cmdCode(_: Allocator, _: []const []const u8, _: anytype, stderr: anytype) !void {
    try stderr.print("Error: Authorization Code Flow not yet implemented\n", .{});
    return error.NotImplemented;
}

fn cmdToken(allocator: Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !void {
    if (args.len < 2) {
        try stderr.print("Error: Missing token action\n\n", .{});
        try stderr.print("USAGE:\n    schlussel token <action> [options]\n\n", .{});
        try stderr.print("ACTIONS:\n", .{});
        try stderr.print("    get     Retrieve a stored token\n", .{});
        try stderr.print("    list    List all stored tokens\n", .{});
        try stderr.print("    delete  Delete a stored token\n", .{});
        return error.MissingArguments;
    }

    const action = args[1];

    if (std.mem.eql(u8, action, "get")) {
        return cmdTokenGet(allocator, args, stdout, stderr);
    } else if (std.mem.eql(u8, action, "list")) {
        return cmdTokenList(allocator, stdout, stderr);
    } else if (std.mem.eql(u8, action, "delete")) {
        return cmdTokenDelete(allocator, args, stdout, stderr);
    } else {
        try stderr.print("Error: Unknown token action '{s}'\n", .{action});
        return error.UnknownAction;
    }
}

fn cmdTokenGet(_: Allocator, _: []const []const u8, _: anytype, stderr: anytype) !void {
    try stderr.print("Error: Token get not yet implemented\n", .{});
    return error.NotImplemented;
}

fn cmdTokenList(_: Allocator, _: anytype, stderr: anytype) !void {
    try stderr.print("Error: Token list not yet implemented\n", .{});
    return error.NotImplemented;
}

fn cmdTokenDelete(_: Allocator, _: []const []const u8, _: anytype, stderr: anytype) !void {
    try stderr.print("Error: Token delete not yet implemented\n", .{});
    return error.NotImplemented;
}

fn createPresetConfig(provider: []const u8, client_id: []const u8, scope: []const u8) !oauth.OAuthConfig {
    if (std.mem.eql(u8, provider, "github")) {
        return oauth.OAuthConfig.github(client_id, scope);
    } else if (std.mem.eql(u8, provider, "google")) {
        return oauth.OAuthConfig.google(client_id, scope);
    } else if (std.mem.eql(u8, provider, "microsoft")) {
        return oauth.OAuthConfig.microsoft(client_id, "common", scope);
    } else if (std.mem.eql(u8, provider, "gitlab")) {
        return oauth.OAuthConfig.gitlab(client_id, scope);
    } else if (std.mem.eql(u8, provider, "tuist")) {
        return oauth.OAuthConfig.tuist(client_id, scope);
    } else {
        return error.UnknownProvider;
    }
}
