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
const registration = @import("registration.zig");

const Command = enum {
    device,
    code,
    token,
    register,
    help,

    pub fn fromString(str: []const u8) ?Command {
        const eql = std.mem.eql;
        if (eql(u8, str, "device")) return .device;
        if (eql(u8, str, "code")) return .code;
        if (eql(u8, str, "token")) return .token;
        if (eql(u8, str, "register")) return .register;
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
        .register => try cmdRegister(allocator, args, stdout, stderr),
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
        \\    register            Dynamically register OAuth client
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
        \\    # Register a new OAuth client
        \\    schlussel register https://auth.example.com/register \
        \\      --client-name "My App" \
        \\      --redirect-uri https://example.com/callback \
        \\      --grant-types authorization_code,refresh_token
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

fn cmdRegister(allocator: Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !void {
    if (args.len < 3) {
        try stderr.print("Error: Missing registration endpoint URL\n\n", .{});
        try stderr.print("USAGE:\n    schlussel register <endpoint-url> [options]\n\n", .{});
        try stderr.print("OPTIONS:\n", .{});
        try stderr.print("    --client-name <name>              Human-readable client name\n", .{});
        try stderr.print("    --redirect-uri <uri>              Redirection URI (can be specified multiple times)\n", .{});
        try stderr.print("    --grant-types <types>             Comma-separated grant types\n", .{});
        try stderr.print("    --response-types <types>          Comma-separated response types\n", .{});
        try stderr.print("    --scope <scope>                   OAuth scope\n", .{});
        try stderr.print("    --token-auth-method <method>      Token endpoint auth method\n", .{});
        return error.MissingArguments;
    }

    const endpoint = args[2];

    // Parse options
    var client_name: ?[]const u8 = null;
    var redirect_uris_list: std.ArrayList([]const u8) = .empty;
    defer {
        for (redirect_uris_list.items) |uri| allocator.free(uri);
        redirect_uris_list.deinit(allocator);
    }

    var grant_types_str: ?[]const u8 = null;
    var response_types_str: ?[]const u8 = null;
    var scope: ?[]const u8 = null;
    var token_auth_method: ?[]const u8 = null;

    var i: usize = 3;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (i + 1 >= args.len) {
            try stderr.print("Error: Missing value for option '{s}'\n", .{arg});
            return error.MissingOptionValue;
        }

        if (std.mem.eql(u8, arg, "--client-name")) {
            client_name = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--redirect-uri")) {
            try redirect_uris_list.append(allocator, try allocator.dupe(u8, args[i + 1]));
            i += 1;
        } else if (std.mem.eql(u8, arg, "--grant-types")) {
            grant_types_str = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--response-types")) {
            response_types_str = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--scope")) {
            scope = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--token-auth-method")) {
            token_auth_method = args[i + 1];
            i += 1;
        } else {
            try stderr.print("Error: Unknown option '{s}'\n", .{arg});
            return error.UnknownOption;
        }
    }

    if (redirect_uris_list.items.len == 0) {
        try stderr.print("Error: At least one --redirect-uri is required\n", .{});
        return error.MissingRequiredOptions;
    }

    // Create client metadata
    var metadata = try registration.ClientMetadata.init(allocator);
    defer metadata.deinit();

    if (client_name) |name| metadata.client_name = name;
    metadata.redirect_uris = redirect_uris_list.items;

    // Parse comma-separated grant types
    if (grant_types_str) |types| {
        var types_list: std.ArrayList([]const u8) = .empty;
        defer {
            for (types_list.items) |t| allocator.free(t);
            types_list.deinit(allocator);
        }

        var iter = std.mem.splitScalar(u8, types, ',');
        while (iter.next()) |t| {
            const trimmed = std.mem.trim(u8, t, " ");
            if (trimmed.len > 0) {
                try types_list.append(allocator, try allocator.dupe(u8, trimmed));
            }
        }
        metadata.grant_types = types_list.items;
    }

    // Parse comma-separated response types
    if (response_types_str) |types| {
        var types_list: std.ArrayList([]const u8) = .empty;
        defer {
            for (types_list.items) |t| allocator.free(t);
            types_list.deinit(allocator);
        }

        var iter = std.mem.splitScalar(u8, types, ',');
        while (iter.next()) |t| {
            const trimmed = std.mem.trim(u8, t, " ");
            if (trimmed.len > 0) {
                try types_list.append(allocator, try allocator.dupe(u8, trimmed));
            }
        }
        metadata.response_types = types_list.items;
    }

    if (scope) |s| metadata.scope = s;
    if (token_auth_method) |m| metadata.token_endpoint_auth_method = m;

    // Create registration client
    var reg_client = try registration.DynamicRegistration.init(allocator, endpoint);
    defer reg_client.deinit();

    try stdout.print("\n=== Dynamic Client Registration ===\n\n", .{});
    try stdout.print("Registering client with: {s}\n\n", .{endpoint});

    // Register the client
    var response = reg_client.register(metadata) catch |err| {
        try stderr.print("\nRegistration failed: {s}\n", .{@errorName(err)});
        return err;
    };
    defer response.deinit();

    try stdout.print("=== Registration Successful! ===\n\n", .{});
    try stdout.print("Client ID: {s}\n", .{response.client_id});

    if (response.client_secret) |secret| {
        try stdout.print("Client Secret: {s}\n", .{secret});
        try stdout.print("\nWARNING: Store this secret securely! It will not be shown again.\n", .{});
    }

    if (response.client_id_issued_at) |issued_at| {
        try stdout.print("Issued At: {d}\n", .{issued_at});
    }

    if (response.client_secret_expires_at) |expires_at| {
        try stdout.print("Secret Expires At: {d}\n", .{expires_at});
    }

    if (response.registration_client_uri) |uri| {
        try stdout.print("Registration URI: {s}\n", .{uri});
    }

    try stdout.print("\nYou can now use this client ID with Schlussel:\n", .{});
    try stdout.print("  schlussel device --custom-provider \\", .{});
    try stdout.print("\n    --token-endpoint <token-endpoint> \\", .{});
    try stdout.print("\n    --client-id {s} \\", .{response.client_id});
    if (response.client_secret) |secret| {
        try stdout.print("\n    --client-secret {s}", .{secret});
    }
    try stdout.print("\n", .{});
}
