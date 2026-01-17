//! Command-line interface for Schlussel OAuth operations
//!
//! ## Usage
//!
//! ```bash
//! # Authenticate with a provider
//! schlussel run github --method device_code
//!
//! # Show provider information
//! schlussel info github
//!
//! # Token management
//! schlussel token get --key github_token
//! schlussel token list
//! ```

const std = @import("std");
const clap = @import("clap");
const Allocator = std.mem.Allocator;
const oauth = @import("oauth.zig");
const session = @import("session.zig");
const registration = @import("registration.zig");
const formulas = @import("formulas.zig");
const callback = @import("callback.zig");
const pkce = @import("pkce.zig");
const lock = @import("lock.zig");

/// ANSI color codes for terminal output
const Color = struct {
    const reset = "\x1b[0m";
    const bold = "\x1b[1m";
    const dim = "\x1b[2m";
    const green = "\x1b[32m";
    const yellow = "\x1b[33m";
    const blue = "\x1b[34m";
    const cyan = "\x1b[36m";
    const bold_green = "\x1b[1;32m";
    const bold_yellow = "\x1b[1;33m";
    const bold_cyan = "\x1b[1;36m";
};

/// Check if colors should be enabled based on NO_COLOR env var and TTY detection
fn colorsEnabled() bool {
    // Respect NO_COLOR convention (https://no-color.org/)
    // Use different API for Windows vs POSIX
    const no_color_set = if (@import("builtin").os.tag == .windows)
        std.process.getenvW(std.unicode.utf8ToUtf16LeStringLiteral("NO_COLOR")) != null
    else
        std.posix.getenv("NO_COLOR") != null;

    if (no_color_set) {
        return false;
    }
    // Check if stdout is a TTY
    const stdout = std.fs.File.stdout();
    return stdout.isTty();
}

const TokenOutput = struct {
    access_token: []const u8,
    token_type: []const u8,
    refresh_token: ?[]const u8,
    scope: ?[]const u8,
    expires_at: ?u64,
    expires_in: ?u64,
    id_token: ?[]const u8,
};

const RunResult = struct {
    storage_key: []const u8,
    method: []const u8,
    token: TokenOutput,
};

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
            .type = step.type,
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

/// Resolve script steps for a v2 formula method
fn resolveScriptSteps(
    allocator: Allocator,
    formula: *const formulas.Formula,
    method_name: []const u8,
    client_id_override: ?[]const u8,
    client_secret_override: ?[]const u8,
    scope_override: ?[]const u8,
    redirect_uri: []const u8,
) !ResolvedScript {
    const method = formula.getMethod(method_name) orelse return error.MethodNotFound;

    // Default steps based on method type
    const default_device_steps = [_]formulas.ScriptStep{
        .{ .type = "open_url", .value = "{verification_uri}", .note = null },
        .{ .type = "enter_code", .value = "{user_code}", .note = null },
        .{ .type = "wait_for_token", .value = null, .note = null },
    };
    const default_code_steps = [_]formulas.ScriptStep{
        .{ .type = "open_url", .value = "{authorize_url}", .note = null },
        .{ .type = "wait_for_callback", .value = null, .note = null },
    };
    const default_api_key_steps = [_]formulas.ScriptStep{
        .{ .type = "copy_key", .value = null, .note = "Paste your API key into the agent." },
    };

    // Use method's script if available, otherwise use defaults based on method type
    const steps_source: []const formulas.ScriptStep = if (method.script) |script|
        script
    else if (method.isDeviceCode())
        default_device_steps[0..]
    else if (method.isAuthorizationCode())
        default_code_steps[0..]
    else
        default_api_key_steps[0..];

    var replacements: std.ArrayListUnmanaged(Replacement) = .{};
    defer replacements.deinit(allocator);

    var allocations: std.ArrayListUnmanaged([]const u8) = .{};
    errdefer {
        for (allocations.items) |item| {
            allocator.free(item);
        }
        allocations.deinit(allocator);
    }

    var context = ScriptContext{};

    if (method.isAuthorizationCode()) {
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
            method_name,
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

        context.redirect_uri = resolved_redirect_uri;
        context.authorize_url = authorize_dup;
        context.pkce_verifier = verifier;
        context.state = state_dup;
    } else if (method.isDeviceCode()) {
        var config = try oauth.configFromFormula(
            allocator,
            formula,
            method_name,
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
    }
    // For API key methods, no context needed

    return expandScriptSteps(allocator, steps_source, replacements.items, context, &allocations);
}

fn tokenFromCredential(
    allocator: Allocator,
    method_name: []const u8,
    credential: []const u8,
) !session.Token {
    if (credential.len == 0) {
        return error.InvalidParameter;
    }

    // Use method name as token type for non-OAuth methods
    return session.Token.init(allocator, credential, method_name);
}

fn tokenToOutput(token: session.Token) TokenOutput {
    return .{
        .access_token = token.access_token,
        .token_type = token.token_type,
        .refresh_token = token.refresh_token,
        .scope = token.scope,
        .expires_at = token.expires_at,
        .expires_in = token.expires_in,
        .id_token = token.id_token,
    };
}

/// Map script step type IDs to human-friendly descriptions
fn friendlyStepName(step_type: []const u8) []const u8 {
    if (std.mem.eql(u8, step_type, "open_url")) {
        return "Open browser";
    } else if (std.mem.eql(u8, step_type, "enter_code")) {
        return "Enter verification code";
    } else if (std.mem.eql(u8, step_type, "wait_for_token")) {
        return "Wait for authorization";
    } else if (std.mem.eql(u8, step_type, "wait_for_callback")) {
        return "Wait for callback";
    } else if (std.mem.eql(u8, step_type, "copy_key")) {
        return "Enter credential";
    } else {
        return step_type;
    }
}

/// Generate storage key using conventional format: {formula_id}:{method}:{identity}
fn storageKeyFromFormula(
    allocator: Allocator,
    formula: *const formulas.Formula,
    method_name: []const u8,
    identity: ?[]const u8,
) ![]const u8 {
    if (identity) |id| {
        return std.fmt.allocPrint(allocator, "{s}:{s}:{s}", .{ formula.id, method_name, id });
    } else {
        return std.fmt.allocPrint(allocator, "{s}:{s}", .{ formula.id, method_name });
    }
}

// ============================================================================
// Command definitions using clap
// ============================================================================

const run_params = clap.parseParamsComptime(
    \\-h, --help                      Display this help and exit.
    \\-m, --method <str>              Authentication method (required if multiple methods).
    \\-c, --client <str>              Use a public client from the formula.
    \\-r, --redirect-uri <str>        Redirect URI for auth code (default: http://127.0.0.1:0/callback).
    \\-f, --formula-json <str>        Load a declarative formula JSON.
    \\    --client-id <str>           OAuth client ID override.
    \\    --client-secret <str>       OAuth client secret override.
    \\-s, --scope <str>               OAuth scopes (space-separated).
    \\    --credential <str>          Secret for non-OAuth methods (api_key).
    \\-i, --identity <str>            Identity label for storage key.
    \\    --open-browser <str>        Open the authorization URL (true/false, default: true).
    \\-j, --json                      Emit machine-readable JSON output.
    \\-n, --dry-run                   Show auth steps without executing them.
    \\<str>                           Provider name.
    \\
);

const formula_params = clap.parseParamsComptime(
    \\-h, --help                      Display this help and exit.
    \\-f, --formula-json <str>        Load a declarative formula JSON.
    \\-j, --json                      Output as JSON.
    \\<str>                           Action (list, show).
    \\<str>                           Formula name (for show).
    \\
);

const token_params = clap.parseParamsComptime(
    \\-h, --help                      Display this help and exit.
    \\-k, --key <str>                 Token storage key (e.g., github:device_code:personal).
    \\    --formula <str>             Filter by formula ID (e.g., github).
    \\    --method <str>              Filter by auth method (e.g., device_code).
    \\    --identity <str>            Filter by identity label (e.g., personal).
    \\    --no-refresh                Disable auto-refresh of OAuth2 tokens.
    \\-j, --json                      Output as JSON.
    \\<str>                           Action (get, list, delete).
    \\
);


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Clean up builtin formulas on exit
    defer formulas.deinitBuiltinFormulas();

    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    var stderr_buf: [4096]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const stderr = &stderr_writer.interface;

    // Ensure output is flushed on all exit paths
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printMainUsage(stdout);
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        try printMainUsage(stdout);
        return;
    }

    if (std.mem.eql(u8, command, "run")) {
        try cmdRun(allocator, args[2..], stdout, stderr);
    } else if (std.mem.eql(u8, command, "formula")) {
        try cmdFormula(allocator, args[2..], stdout, stderr);
    } else if (std.mem.eql(u8, command, "token")) {
        try cmdToken(allocator, args[2..], stdout, stderr);
    } else {
        try stderr.print("Error: Unknown command '{s}'\n\n", .{command});
        try printMainUsage(stderr);
        return error.UnknownCommand;
    }
}

fn printMainUsage(writer: anytype) !void {
    try writer.writeAll(
        \\Schlussel Auth Command-Line Tool
        \\
        \\USAGE:
        \\    schlussel <command> [options]
        \\
        \\COMMANDS:
        \\    run                 Authenticate with a provider
        \\    formula <action>    Formula operations (list, show)
        \\    token <action>      Token management (get, list, delete)
        \\    help                Show this help message
        \\
        \\EXAMPLES:
        \\    # List available formulas
        \\    schlussel formula list
        \\
        \\    # Show details for a formula
        \\    schlussel formula show github
        \\
        \\    # Authenticate with GitHub using device code flow
        \\    schlussel run github --method device_code
        \\
        \\    # Authenticate with Linear using OAuth
        \\    schlussel run linear --method oauth --identity acme
        \\
        \\    # Get a stored token
        \\    schlussel token get --formula github --method device_code
        \\
        \\For more help, visit: https://github.com/pepicrft/schlussel
        \\
    );
}

fn cmdRun(allocator: Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !void {
    var diag: clap.Diagnostic = .{};
    var iter = clap.args.SliceIterator{ .args = args };
    var res = clap.parseEx(clap.Help, &run_params, clap.parsers.default, &iter, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        diag.report(stderr, err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try clap.help(stdout, clap.Help, &run_params, .{});
        return;
    }

    const provider_name = if (res.positionals.len > 0) res.positionals[0] orelse {
        try stderr.print("Error: Missing provider name\n\n", .{});
        try clap.help(stderr, clap.Help, &run_params, .{});
        return error.MissingArguments;
    } else {
        try stderr.print("Error: Missing provider name\n\n", .{});
        try clap.help(stderr, clap.Help, &run_params, .{});
        return error.MissingArguments;
    };

    var client_id_override = res.args.@"client-id";
    var client_secret_override = res.args.@"client-secret";
    const scope_override = res.args.scope;
    var redirect_uri: []const u8 = res.args.@"redirect-uri" orelse "http://127.0.0.1:0/callback";
    const credential_override = res.args.credential;
    const identity_override = res.args.identity;
    const json_output = res.args.json != 0;
    const dry_run = res.args.@"dry-run" != 0;

    var open_browser = true;
    if (res.args.@"open-browser") |value| {
        if (std.mem.eql(u8, value, "true")) {
            open_browser = true;
        } else if (std.mem.eql(u8, value, "false")) {
            open_browser = false;
        } else {
            try stderr.print("Error: --open-browser must be true or false\n", .{});
            return error.InvalidParameter;
        }
    }

    // Load formula
    var thirdPartyFormula: ?formulas.FormulaOwned = null;
    defer if (thirdPartyFormula) |*owner| owner.deinit();

    if (res.args.@"formula-json") |path| {
        thirdPartyFormula = try formulas.loadFromPath(allocator, path);
    }

    var formula_ptr: ?*const formulas.Formula = null;
    if (thirdPartyFormula) |owner| {
        if (!std.mem.eql(u8, owner.formula.id, provider_name)) {
            try stderr.print(
                "Warning: formula id '{s}' does not match provider '{s}'\n",
                .{ owner.formula.id, provider_name },
            );
        }
        formula_ptr = owner.asConst();
    } else {
        formula_ptr = try formulas.findById(allocator, provider_name);
    }

    const formula = formula_ptr orelse {
        try stderr.print("Error: Unknown provider '{s}'\n", .{provider_name});
        return error.UnknownProvider;
    };

    // If --client is specified, look up the client and use its credentials
    // If no client specified and no client-id override, auto-select first available public client
    var selected_client: ?formulas.Client = null;
    if (res.args.client) |client_name| {
        if (formula.clients) |clients| {
            for (clients) |client| {
                if (std.mem.eql(u8, client.name, client_name)) {
                    selected_client = client;
                    // Use client's credentials if not explicitly overridden
                    if (client_id_override == null) {
                        client_id_override = client.id;
                    }
                    if (client_secret_override == null) {
                        client_secret_override = client.secret;
                    }
                    // Use client's redirect_uri if not explicitly overridden
                    if (res.args.@"redirect-uri" == null) {
                        if (client.redirect_uri) |uri| {
                            redirect_uri = uri;
                        }
                    }
                    break;
                }
            }
            if (selected_client == null) {
                try stderr.print("Error: Unknown client '{s}'\n", .{client_name});
                try stderr.print("Available clients: ", .{});
                for (clients, 0..) |client, idx| {
                    if (idx > 0) try stderr.print(", ", .{});
                    try stderr.print("{s}", .{client.name});
                }
                try stderr.print("\n", .{});
                return error.InvalidParameter;
            }
        } else {
            try stderr.print("Error: Provider '{s}' has no public clients defined\n", .{provider_name});
            return error.InvalidParameter;
        }
    } else if (client_id_override == null) {
        // No explicit client or client-id specified, auto-select first public client if available
        if (formula.clients) |clients| {
            if (clients.len > 0) {
                selected_client = clients[0];
                client_id_override = clients[0].id;
                client_secret_override = clients[0].secret;
                if (res.args.@"redirect-uri" == null) {
                    if (clients[0].redirect_uri) |uri| {
                        redirect_uri = uri;
                    }
                }
            }
        }
    }

    // Helper to check if a method is supported by the selected client
    const clientSupportsMethod = struct {
        fn check(client: ?formulas.Client, method_to_check: []const u8) bool {
            if (client) |c| {
                if (c.methods) |client_methods| {
                    for (client_methods) |cm| {
                        if (std.mem.eql(u8, cm, method_to_check)) {
                            return true;
                        }
                    }
                    return false;
                }
            }
            return true; // No client or no method restrictions
        }
    }.check;

    // Determine method to use
    var method_name: []const u8 = undefined;
    if (res.args.method) |m| {
        // Verify the method exists
        if (formula.getMethod(m) == null) {
            try stderr.print("Error: Unknown method '{s}'\n", .{m});
            try stderr.print("Available methods: ", .{});
            for (formula.methods, 0..) |method, idx| {
                if (idx > 0) try stderr.print(", ", .{});
                try stderr.print("{s}", .{method.name});
            }
            try stderr.print("\n", .{});
            return error.InvalidMethod;
        }
        // If a client is selected, verify it supports this method
        if (!clientSupportsMethod(selected_client, m)) {
            try stderr.print("Error: Client '{s}' does not support method '{s}'\n", .{ res.args.client.?, m });
            if (selected_client) |c| {
                if (c.methods) |client_methods| {
                    try stderr.print("Supported methods: ", .{});
                    for (client_methods, 0..) |cm, idx| {
                        if (idx > 0) try stderr.print(", ", .{});
                        try stderr.print("{s}", .{cm});
                    }
                    try stderr.print("\n", .{});
                }
            }
            return error.InvalidMethod;
        }
        method_name = m;
    } else {
        // Auto-select method based on available methods (filtered by client if applicable)
        var compatible_count: usize = 0;
        var last_compatible: []const u8 = undefined;
        for (formula.methods) |method| {
            if (clientSupportsMethod(selected_client, method.name)) {
                compatible_count += 1;
                last_compatible = method.name;
            }
        }

        if (compatible_count == 1) {
            method_name = last_compatible;
        } else if (compatible_count == 0) {
            try stderr.print("Error: No methods available", .{});
            if (selected_client) |c| {
                try stderr.print(" for client '{s}'", .{c.name});
            }
            try stderr.print("\n", .{});
            return error.InvalidMethod;
        } else {
            try stderr.print("Error: --method is required when multiple methods are available\n", .{});
            try stderr.print("Available methods: ", .{});
            var first = true;
            for (formula.methods) |method| {
                if (clientSupportsMethod(selected_client, method.name)) {
                    if (!first) try stderr.print(", ", .{});
                    try stderr.print("{s}", .{method.name});
                    first = false;
                }
            }
            try stderr.print("\n", .{});
            return error.MissingArguments;
        }
    }

    const method = formula.getMethod(method_name).?;

    var resolved_script = try resolveScriptSteps(
        allocator,
        formula,
        method_name,
        client_id_override,
        client_secret_override,
        scope_override,
        redirect_uri,
    );
    defer resolved_script.deinit();

    const script_steps = resolved_script.steps;
    const context = resolved_script.context;

    const storage_key = try storageKeyFromFormula(allocator, formula, method_name, identity_override);
    defer allocator.free(storage_key);

    const resolved_redirect_uri = context.redirect_uri orelse "http://127.0.0.1:0/callback";
    var owned_config = oauth.configFromFormula(
        allocator,
        formula,
        method_name,
        client_id_override,
        client_secret_override,
        resolved_redirect_uri,
        scope_override,
    ) catch |err| {
        if (err == error.MissingClientId) {
            try stderr.print("Error: --client-id is required (formula does not provide one)\n", .{});
            return error.MissingRequiredOptions;
        }
        return err;
    };
    defer owned_config.deinit();

    var storage = try session.FileStorage.init(allocator, "schlussel");
    defer storage.deinit();

    var client = oauth.OAuthClient.init(allocator, owned_config.toConfig(), storage.storage());
    defer client.deinit();

    const info_out = if (json_output) stderr else stdout;
    var token: session.Token = undefined;
    const use_color = colorsEnabled() and !json_output;

    if (script_steps.len > 0) {
        if (use_color) {
            try info_out.print("\n{s}Script steps:{s}\n", .{ Color.bold, Color.reset });
        } else {
            try info_out.print("\nScript steps:\n", .{});
        }
        for (script_steps, 0..) |step, idx| {
            const friendly_name = friendlyStepName(step.type);
            if (use_color) {
                if (step.note) |note| {
                    try info_out.print("  {s}{d}.{s} {s} {s}({s}){s}\n", .{ Color.cyan, idx + 1, Color.reset, friendly_name, Color.dim, note, Color.reset });
                } else {
                    try info_out.print("  {s}{d}.{s} {s}\n", .{ Color.cyan, idx + 1, Color.reset, friendly_name });
                }
            } else {
                if (step.note) |note| {
                    try info_out.print("  {d}. {s} ({s})\n", .{ idx + 1, friendly_name, note });
                } else {
                    try info_out.print("  {d}. {s}\n", .{ idx + 1, friendly_name });
                }
            }
        }
    }

    // Dry run mode: show what would happen without executing
    if (dry_run) {
        if (method.isDeviceCode()) {
            const verification_uri = context.verification_uri orelse {
                try stderr.print("Error: script context missing verification_uri\n", .{});
                return error.InvalidParameter;
            };
            const user_code = context.user_code orelse {
                try stderr.print("Error: script context missing user_code\n", .{});
                return error.InvalidParameter;
            };

            if (use_color) {
                try stdout.print("\n{s}[DRY RUN]{s} Would authorize via device code:\n", .{ Color.bold_yellow, Color.reset });
                try stdout.print("  {s}Verification URL:{s} {s}{s}{s}\n", .{ Color.dim, Color.reset, Color.cyan, verification_uri, Color.reset });
                try stdout.print("  {s}User code:{s} {s}{s}{s}\n", .{ Color.dim, Color.reset, Color.bold_yellow, user_code, Color.reset });
                if (context.verification_uri_complete) |uri| {
                    try stdout.print("  {s}Direct URL:{s} {s}{s}{s}\n", .{ Color.dim, Color.reset, Color.cyan, uri, Color.reset });
                }
                try stdout.print("\n{s}Token would be saved with key:{s} {s}{s}{s}\n", .{ Color.dim, Color.reset, Color.cyan, storage_key, Color.reset });
            } else {
                try stdout.print("\n[DRY RUN] Would authorize via device code:\n", .{});
                try stdout.print("  Verification URL: {s}\n", .{verification_uri});
                try stdout.print("  User code: {s}\n", .{user_code});
                if (context.verification_uri_complete) |uri| {
                    try stdout.print("  Direct URL: {s}\n", .{uri});
                }
                try stdout.print("\nToken would be saved with key: {s}\n", .{storage_key});
            }
        } else if (method.isAuthorizationCode()) {
            const authorize_url = context.authorize_url orelse {
                try stderr.print("Error: script context missing authorize_url\n", .{});
                return error.InvalidParameter;
            };

            if (use_color) {
                try stdout.print("\n{s}[DRY RUN]{s} Would authorize via browser:\n", .{ Color.bold_yellow, Color.reset });
                try stdout.print("  {s}Authorization URL:{s}\n  {s}{s}{s}\n", .{ Color.dim, Color.reset, Color.cyan, authorize_url, Color.reset });
                try stdout.print("\n{s}Token would be saved with key:{s} {s}{s}{s}\n", .{ Color.dim, Color.reset, Color.cyan, storage_key, Color.reset });
            } else {
                try stdout.print("\n[DRY RUN] Would authorize via browser:\n", .{});
                try stdout.print("  Authorization URL:\n  {s}\n", .{authorize_url});
                try stdout.print("\nToken would be saved with key: {s}\n", .{storage_key});
            }
        } else {
            const label = method.label orelse "credential";
            if (use_color) {
                try stdout.print("\n{s}[DRY RUN]{s} Would prompt for: {s}{s}{s}\n", .{ Color.bold_yellow, Color.reset, Color.cyan, label, Color.reset });
                try stdout.print("\n{s}Token would be saved with key:{s} {s}{s}{s}\n", .{ Color.dim, Color.reset, Color.cyan, storage_key, Color.reset });
            } else {
                try stdout.print("\n[DRY RUN] Would prompt for: {s}\n", .{label});
                try stdout.print("\nToken would be saved with key: {s}\n", .{storage_key});
            }
        }
        return;
    }

    if (method.isDeviceCode()) {
        const device_code = context.device_code orelse {
            try stderr.print("Error: script context missing device_code\n", .{});
            return error.InvalidParameter;
        };
        const verification_uri = context.verification_uri orelse {
            try stderr.print("Error: script context missing verification_uri\n", .{});
            return error.InvalidParameter;
        };
        const user_code = context.user_code orelse {
            try stderr.print("Error: script context missing user_code\n", .{});
            return error.InvalidParameter;
        };

        // Display authorization instructions
        if (use_color) {
            try info_out.print("\n{s}To authorize, visit:{s} {s}{s}{s}\n", .{ Color.bold, Color.reset, Color.cyan, verification_uri, Color.reset });
            try info_out.print("{s}And enter code:{s} {s}{s}{s}\n\n", .{ Color.bold, Color.reset, Color.bold_yellow, user_code, Color.reset });
            try info_out.print("{s}Waiting for authorization...{s}\n", .{ Color.dim, Color.reset });
        } else {
            try info_out.print("\nTo authorize, visit: {s}\n", .{verification_uri});
            try info_out.print("And enter code: {s}\n\n", .{user_code});
            try info_out.print("Waiting for authorization...\n", .{});
        }
        try info_out.flush();

        // Open browser if enabled
        if (open_browser) {
            if (context.verification_uri_complete) |uri| {
                callback.openBrowser(uri) catch {};
            } else {
                callback.openBrowser(verification_uri) catch {};
            }
        }

        const interval = context.interval orelse 5;
        token = client.pollDeviceCode(device_code, interval, context.expires_in) catch |err| {
            try stderr.print("\nAuthorization failed: {s}\n", .{@errorName(err)});
            return err;
        };
    } else if (method.isAuthorizationCode()) {
        const authorize_url = context.authorize_url orelse {
            try stderr.print("Error: script context missing authorize_url\n", .{});
            return error.InvalidParameter;
        };
        const pkce_verifier = context.pkce_verifier orelse {
            try stderr.print("Error: script context missing pkce_verifier\n", .{});
            return error.InvalidParameter;
        };
        const state = context.state orelse {
            try stderr.print("Error: script context missing state\n", .{});
            return error.InvalidParameter;
        };
        const callback_uri = context.redirect_uri orelse {
            try stderr.print("Error: script context missing redirect_uri\n", .{});
            return error.InvalidParameter;
        };

        const port = try parseRedirectPort(callback_uri);
        var server = try callback.CallbackServer.init(allocator, port);
        defer server.deinit();

        if (open_browser) {
            if (use_color) {
                try info_out.print("\n{s}Opening browser for authorization...{s}\n", .{ Color.dim, Color.reset });
                try info_out.print("If the browser doesn't open, visit:\n{s}{s}{s}\n\n", .{ Color.cyan, authorize_url, Color.reset });
                try info_out.print("{s}Waiting for authorization...{s}\n", .{ Color.dim, Color.reset });
            } else {
                try info_out.print("\nOpening browser for authorization...\n", .{});
                try info_out.print("If the browser doesn't open, visit:\n{s}\n\n", .{authorize_url});
                try info_out.print("Waiting for authorization...\n", .{});
            }
            try info_out.flush();
            callback.openBrowser(authorize_url) catch {};
        } else {
            if (use_color) {
                try info_out.print("\n{s}Visit the following URL to authorize:{s}\n{s}{s}{s}\n\n", .{ Color.bold, Color.reset, Color.cyan, authorize_url, Color.reset });
                try info_out.print("{s}Waiting for authorization...{s}\n", .{ Color.dim, Color.reset });
            } else {
                try info_out.print("\nVisit the following URL to authorize:\n{s}\n\n", .{authorize_url});
                try info_out.print("Waiting for authorization...\n", .{});
            }
            try info_out.flush();
        }

        var result = try server.waitForCallback(120);
        defer result.deinit();

        if (result.state) |callback_state| {
            if (!std.mem.eql(u8, callback_state, state)) {
                return error.InvalidState;
            }
        }

        if (result.error_code != null) {
            return error.AuthorizationDenied;
        }

        const code = result.code orelse return error.ServerError;
        token = client.exchangeCode(code, pkce_verifier, callback_uri) catch |err| {
            try stderr.print("\nAuthorization failed: {s}\n", .{@errorName(err)});
            return err;
        };
    } else {
        // API key or similar manual credential
        var secret_owned: ?[]const u8 = null;
        defer if (secret_owned) |value| allocator.free(value);
        const secret = credential_override orelse blk: {
            const label = method.label orelse "credential";
            try info_out.print("\nEnter {s}: ", .{label});
            const stdin = std.fs.File.stdin();
            var line_buf: [4096]u8 = undefined;
            var line_len: usize = 0;
            while (line_len < line_buf.len) {
                const n = stdin.read(line_buf[line_len .. line_len + 1]) catch |err| {
                    return err;
                };
                if (n == 0) break;
                if (line_buf[line_len] == '\n') break;
                line_len += 1;
            }
            if (line_len == 0) return error.EndOfStream;
            const line = line_buf[0..line_len];
            const trimmed = std.mem.trimRight(u8, line, "\r\n");
            if (trimmed.len == 0) {
                try stderr.print("Error: credential cannot be empty\n", .{});
                return error.InvalidParameter;
            }
            secret_owned = try allocator.dupe(u8, trimmed);
            break :blk secret_owned.?;
        };

        token = try tokenFromCredential(allocator, method_name, secret);
    }
    defer token.deinit();

    try client.saveToken(storage_key, token);
    if (json_output) {
        const run_result = RunResult{
            .storage_key = storage_key,
            .method = method_name,
            .token = tokenToOutput(token),
        };
        var out = std.Io.Writer.Allocating.init(allocator);
        defer out.deinit();
        try std.json.Stringify.value(run_result, .{ .whitespace = .indent_2 }, &out.writer);
        try stdout.print("{s}\n", .{out.written()});
    } else {
        if (use_color) {
            try stdout.print("\n{s}=== Authorization Successful! ==={s}\n\n", .{ Color.bold_green, Color.reset });
            try stdout.print("{s}Token type:{s} {s}\n", .{ Color.dim, Color.reset, token.token_type });
            if (token.scope) |s| {
                try stdout.print("{s}Scope:{s} {s}\n", .{ Color.dim, Color.reset, s });
            }
            if (token.expires_at) |expires_at| {
                try stdout.print("{s}Expires at:{s} {d} (Unix timestamp)\n", .{ Color.dim, Color.reset, expires_at });
            }
            try stdout.print("\n{s}Token saved with key:{s} {s}{s}{s}\n", .{ Color.dim, Color.reset, Color.cyan, storage_key, Color.reset });
        } else {
            try stdout.print("\n=== Authorization Successful! ===\n\n", .{});
            try stdout.print("Token type: {s}\n", .{token.token_type});
            if (token.scope) |s| {
                try stdout.print("Scope: {s}\n", .{s});
            }
            if (token.expires_at) |expires_at| {
                try stdout.print("Expires at: {d} (Unix timestamp)\n", .{expires_at});
            }
            try stdout.print("\nToken saved with key: {s}\n", .{storage_key});
        }
    }
}

fn cmdFormula(allocator: Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !void {
    var diag: clap.Diagnostic = .{};
    var iter = clap.args.SliceIterator{ .args = args };
    var res = clap.parseEx(clap.Help, &formula_params, clap.parsers.default, &iter, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        diag.report(stderr, err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try clap.help(stdout, clap.Help, &formula_params, .{});
        return;
    }

    const action = if (res.positionals.len > 0) res.positionals[0] orelse {
        try stderr.print("Error: Missing action (list, show)\n\n", .{});
        try clap.help(stderr, clap.Help, &formula_params, .{});
        return error.MissingArguments;
    } else {
        try stderr.print("Error: Missing action (list, show)\n\n", .{});
        try clap.help(stderr, clap.Help, &formula_params, .{});
        return error.MissingArguments;
    };

    const json_output = res.args.json != 0;

    if (std.mem.eql(u8, action, "list")) {
        // List all available formulas
        const formula_list = try formulas.listAll(allocator);
        defer {
            for (formula_list) |f| {
                allocator.free(f.id);
                allocator.free(f.label);
            }
            allocator.free(formula_list);
        }

        if (json_output) {
            try stdout.print("[\n", .{});
            for (formula_list, 0..) |f, idx| {
                try stdout.print("  {{\"id\": \"{s}\", \"label\": \"{s}\"}}", .{ f.id, f.label });
                if (idx < formula_list.len - 1) try stdout.print(",", .{});
                try stdout.print("\n", .{});
            }
            try stdout.print("]\n", .{});
        } else {
            try stdout.print("Available formulas:\n", .{});
            for (formula_list) |f| {
                try stdout.print("  {s} - {s}\n", .{ f.id, f.label });
            }
        }
    } else if (std.mem.eql(u8, action, "show")) {
        const provider_arg = if (res.positionals.len > 1) res.positionals[1] orelse {
            try stderr.print("Error: Missing formula name\n", .{});
            return error.MissingArguments;
        } else {
            try stderr.print("Error: Missing formula name\n", .{});
            return error.MissingArguments;
        };

        var thirdPartyFormula: ?formulas.FormulaOwned = null;
        defer if (thirdPartyFormula) |*owner| owner.deinit();

        var formula_ptr: ?*const formulas.Formula = null;
        if (res.args.@"formula-json") |path| {
            thirdPartyFormula = try formulas.loadFromPath(allocator, path);
            formula_ptr = thirdPartyFormula.?.asConst();
        } else {
            formula_ptr = try formulas.findById(allocator, provider_arg);
        }

        const formula = formula_ptr orelse {
            try stderr.print("Error: Unknown formula '{s}'\n", .{provider_arg});
            return error.UnknownProvider;
        };

        if (json_output) {
            // Output structured JSON
            try stdout.print("{{\n", .{});
            try stdout.print("  \"id\": \"{s}\",\n", .{formula.id});
            try stdout.print("  \"label\": \"{s}\",\n", .{formula.label});

            // Methods
            try stdout.print("  \"methods\": [\n", .{});
            for (formula.methods, 0..) |method, idx| {
                try stdout.print("    {{\n", .{});
                try stdout.print("      \"name\": \"{s}\"", .{method.name});
                if (method.label) |label| {
                    try stdout.print(",\n      \"label\": \"{s}\"", .{label});
                }
                if (method.isDeviceCode()) {
                    try stdout.print(",\n      \"type\": \"device_code\"", .{});
                } else if (method.isAuthorizationCode()) {
                    try stdout.print(",\n      \"type\": \"authorization_code\"", .{});
                } else {
                    try stdout.print(",\n      \"type\": \"api_key\"", .{});
                }
                try stdout.print("\n    }}", .{});
                if (idx < formula.methods.len - 1) try stdout.print(",", .{});
                try stdout.print("\n", .{});
            }
            try stdout.print("  ],\n", .{});

            // APIs
            try stdout.print("  \"apis\": [\n", .{});
            for (formula.apis, 0..) |api, idx| {
                try stdout.print("    {{\n", .{});
                try stdout.print("      \"name\": \"{s}\",\n", .{api.name});
                try stdout.print("      \"base_url\": \"{s}\",\n", .{api.base_url});
                try stdout.print("      \"methods\": [", .{});
                for (api.methods, 0..) |m, midx| {
                    try stdout.print("\"{s}\"", .{m});
                    if (midx < api.methods.len - 1) try stdout.print(", ", .{});
                }
                try stdout.print("]\n    }}", .{});
                if (idx < formula.apis.len - 1) try stdout.print(",", .{});
                try stdout.print("\n", .{});
            }
            try stdout.print("  ]\n", .{});
            try stdout.print("}}\n", .{});
        } else {
            // Human-readable output
            try stdout.print("\n{s}\n", .{formula.label});
            try stdout.print("ID: {s}\n\n", .{formula.id});

            if (formula.identity) |identity| {
                if (identity.label) |label| {
                    try stdout.print("Identity: {s}", .{label});
                    if (identity.hint) |hint| {
                        try stdout.print(" ({s})", .{hint});
                    }
                    try stdout.print("\n\n", .{});
                }
            }

            try stdout.print("Methods:\n", .{});
            for (formula.methods) |method| {
                const label = method.label orelse method.name;
                try stdout.print("  - {s}", .{label});
                if (method.isDeviceCode()) {
                    try stdout.print(" (device code)", .{});
                } else if (method.isAuthorizationCode()) {
                    try stdout.print(" (authorization code)", .{});
                } else {
                    try stdout.print(" (manual)", .{});
                }
                try stdout.print("\n", .{});
            }

            try stdout.print("\nAPIs:\n", .{});
            for (formula.apis) |api| {
                try stdout.print("  - {s}: {s}\n", .{ api.name, api.base_url });
                try stdout.print("    Methods: ", .{});
                for (api.methods, 0..) |m, idx| {
                    if (idx > 0) try stdout.print(", ", .{});
                    try stdout.print("{s}", .{m});
                }
                try stdout.print("\n", .{});
            }

            if (formula.clients) |clients| {
                try stdout.print("\nPublic Clients:\n", .{});
                for (clients) |client| {
                    try stdout.print("  - {s}", .{client.name});
                    if (client.source) |source| {
                        try stdout.print(" (from {s})", .{source});
                    }
                    try stdout.print("\n", .{});
                }
            }
        }
    } else {
        try stderr.print("Error: Unknown action '{s}'. Use: list, show\n", .{action});
        return error.InvalidParameter;
    }
}

/// Parse a storage key into its components (formula, method, identity)
fn parseStorageKey(key: []const u8) struct { formula: []const u8, method: ?[]const u8, identity: ?[]const u8 } {
    var parts_iter = std.mem.splitScalar(u8, key, ':');
    const formula = parts_iter.first();
    const method = parts_iter.next();
    const identity = parts_iter.next();
    return .{ .formula = formula, .method = method, .identity = identity };
}

/// Build a storage key from components
fn buildStorageKey(allocator: Allocator, formula: []const u8, method: ?[]const u8, identity: ?[]const u8) ![]const u8 {
    if (method) |m| {
        if (identity) |i| {
            return std.fmt.allocPrint(allocator, "{s}:{s}:{s}", .{ formula, m, i });
        }
        return std.fmt.allocPrint(allocator, "{s}:{s}", .{ formula, m });
    }
    return allocator.dupe(u8, formula);
}

/// Check if a key matches the given filter criteria
fn keyMatchesFilter(key: []const u8, formula_filter: ?[]const u8, method_filter: ?[]const u8, identity_filter: ?[]const u8) bool {
    const parsed = parseStorageKey(key);

    if (formula_filter) |f| {
        if (!std.mem.eql(u8, parsed.formula, f)) return false;
    }
    if (method_filter) |m| {
        if (parsed.method == null or !std.mem.eql(u8, parsed.method.?, m)) return false;
    }
    if (identity_filter) |i| {
        if (parsed.identity == null or !std.mem.eql(u8, parsed.identity.?, i)) return false;
    }
    return true;
}

/// List all token files in storage directory
fn listTokenFiles(allocator: Allocator, storage_path: []const u8) ![][]const u8 {
    var keys: std.ArrayListUnmanaged([]const u8) = .{};
    errdefer {
        for (keys.items) |k| allocator.free(k);
        keys.deinit(allocator);
    }

    var dir = std.fs.cwd().openDir(storage_path, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) return keys.toOwnedSlice(allocator);
        return err;
    };
    defer dir.close();

    var dir_iter = dir.iterate();
    while (try dir_iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".json")) continue;

        // Remove .json extension to get the key
        const token_key = entry.name[0 .. entry.name.len - 5];
        try keys.append(allocator, try allocator.dupe(u8, token_key));
    }

    return keys.toOwnedSlice(allocator);
}

/// Get the storage path for schlussel
fn getTokenStoragePath(allocator: Allocator) ![]const u8 {
    const builtin = @import("builtin");

    if (builtin.os.tag == .linux) {
        if (std.process.getEnvVarOwned(allocator, "XDG_DATA_HOME")) |xdg_data| {
            defer allocator.free(xdg_data);
            return std.fmt.allocPrint(allocator, "{s}/schlussel", .{xdg_data});
        } else |_| {}
        if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
            defer allocator.free(home);
            return std.fmt.allocPrint(allocator, "{s}/.local/share/schlussel", .{home});
        } else |_| {}
    } else if (builtin.os.tag == .macos) {
        if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
            defer allocator.free(home);
            return std.fmt.allocPrint(allocator, "{s}/Library/Application Support/schlussel", .{home});
        } else |_| {}
    } else if (builtin.os.tag == .windows) {
        if (std.process.getEnvVarOwned(allocator, "LOCALAPPDATA")) |local_app_data| {
            defer allocator.free(local_app_data);
            return std.fmt.allocPrint(allocator, "{s}\\schlussel", .{local_app_data});
        } else |_| {}
    }

    return std.fmt.allocPrint(allocator, "/tmp/schlussel", .{});
}

fn outputToken(stdout: anytype, key: []const u8, token: session.Token, json_output: bool) !void {
    if (json_output) {
        try stdout.print("{{\n", .{});
        try stdout.print("  \"key\": \"{s}\",\n", .{key});
        try stdout.print("  \"access_token\": \"{s}\",\n", .{token.access_token});
        try stdout.print("  \"token_type\": \"{s}\"", .{token.token_type});
        if (token.refresh_token) |rt| {
            try stdout.print(",\n  \"refresh_token\": \"{s}\"", .{rt});
        }
        if (token.scope) |s| {
            try stdout.print(",\n  \"scope\": \"{s}\"", .{s});
        }
        if (token.expires_at) |exp| {
            try stdout.print(",\n  \"expires_at\": {d}", .{exp});
        }
        if (token.expires_in) |exp| {
            try stdout.print(",\n  \"expires_in\": {d}", .{exp});
        }
        try stdout.print("\n}}\n", .{});
    } else {
        try stdout.print("{s}\n", .{token.access_token});
    }
}

fn cmdToken(allocator: Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !void {
    var diag: clap.Diagnostic = .{};
    var iter = clap.args.SliceIterator{ .args = args };
    var res = clap.parseEx(clap.Help, &token_params, clap.parsers.default, &iter, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        diag.report(stderr, err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try clap.help(stdout, clap.Help, &token_params, .{});
        return;
    }

    const action = if (res.positionals.len > 0) res.positionals[0] orelse {
        try stderr.print("Error: Missing action (get, list, delete)\n\n", .{});
        try clap.help(stderr, clap.Help, &token_params, .{});
        return error.MissingArguments;
    } else {
        try stderr.print("Error: Missing action (get, list, delete)\n\n", .{});
        try clap.help(stderr, clap.Help, &token_params, .{});
        return error.MissingArguments;
    };

    const key_arg = res.args.key;
    const formula_filter = res.args.formula;
    const method_filter = res.args.method;
    const identity_filter = res.args.identity;
    const auto_refresh = res.args.@"no-refresh" == 0; // Refresh by default
    const json_output = res.args.json != 0;

    var storage = try session.FileStorage.init(allocator, "schlussel");
    defer storage.deinit();

    const storage_path = try getTokenStoragePath(allocator);
    defer allocator.free(storage_path);

    if (std.mem.eql(u8, action, "get")) {
        // Determine the key to use
        var key: []const u8 = undefined;
        var key_owned = false;

        if (key_arg) |k| {
            key = k;
        } else if (formula_filter != null) {
            // Build key from components
            key = try buildStorageKey(allocator, formula_filter.?, method_filter, identity_filter);
            key_owned = true;
        } else {
            try stderr.print("Error: Either --key or --formula is required for 'get'\n", .{});
            return error.MissingArguments;
        }
        defer if (key_owned) allocator.free(key);

        var token = (try storage.storage().load(allocator, key)) orelse {
            try stderr.print("Error: Token not found for key '{s}'\n", .{key});
            return error.NotFound;
        };
        defer token.deinit();

        // Auto-refresh if requested and token is OAuth2 with refresh_token
        if (auto_refresh and token.refresh_token != null) {
            const now = @as(u64, @intCast(std.time.timestamp()));
            const needs_refresh = if (token.expires_at) |expires_at|
                now + 300 >= expires_at // Refresh if expiring within 5 minutes
            else
                false;

            if (needs_refresh) {
                // Acquire cross-process lock before refreshing
                var lock_manager = try lock.RefreshLockManager.init(allocator, "schlussel");
                defer lock_manager.deinit();

                // Convert key colons to underscores for lock file name
                var lock_key_buf: [256]u8 = undefined;
                var lock_key_len: usize = 0;
                for (key) |c| {
                    if (lock_key_len >= lock_key_buf.len) break;
                    lock_key_buf[lock_key_len] = if (c == ':') '_' else c;
                    lock_key_len += 1;
                }
                const lock_key = lock_key_buf[0..lock_key_len];

                var refresh_lock = try lock_manager.acquire(lock_key);
                defer refresh_lock.release();

                // Re-check if token still needs refresh (another process may have refreshed it)
                var fresh_token = (try storage.storage().load(allocator, key)) orelse {
                    try stderr.print("Error: Token not found after acquiring lock\n", .{});
                    return error.NotFound;
                };

                const still_needs_refresh = if (fresh_token.expires_at) |expires_at|
                    now + 300 >= expires_at
                else
                    false;

                if (still_needs_refresh and fresh_token.refresh_token != null) {
                    // Parse key to get formula and method for OAuth config
                    const parsed = parseStorageKey(key);

                    // Try to find the formula to get token endpoint
                    const formula_ptr = formulas.findById(allocator, parsed.formula) catch null;
                    if (formula_ptr) |formula| {
                        const method_name = parsed.method orelse "oauth";

                        var owned_config = oauth.configFromFormula(
                            allocator,
                            formula,
                            method_name,
                            null, // client_id - use formula default
                            null, // client_secret
                            "http://127.0.0.1:0/callback",
                            null, // scope
                        ) catch {
                            // Can't build config, return existing token
                            token.deinit();
                            token = fresh_token;
                            if (!json_output) {
                                try stderr.print("Warning: Could not refresh token (missing OAuth config)\n", .{});
                            }
                            try outputToken(stdout, key, token, json_output);
                            return;
                        };
                        defer owned_config.deinit();

                        var mem_storage = session.MemoryStorage.init(allocator);
                        defer mem_storage.deinit();

                        var client = oauth.OAuthClient.init(allocator, owned_config.toConfig(), mem_storage.storage());
                        defer client.deinit();

                        // Perform refresh
                        var new_token = client.refreshToken(fresh_token.refresh_token.?) catch |err| {
                            // Refresh failed, return existing token
                            token.deinit();
                            token = fresh_token;
                            if (!json_output) {
                                try stderr.print("Warning: Token refresh failed: {s}\n", .{@errorName(err)});
                            }
                            try outputToken(stdout, key, token, json_output);
                            return;
                        };

                        // Preserve refresh token if not in response
                        if (new_token.refresh_token == null and fresh_token.refresh_token != null) {
                            new_token.refresh_token = try allocator.dupe(u8, fresh_token.refresh_token.?);
                        }

                        // Save new token
                        try storage.storage().save(key, new_token);

                        fresh_token.deinit();
                        token.deinit();
                        token = new_token;

                        if (!json_output) {
                            try stderr.print("Token refreshed successfully\n", .{});
                        }
                    } else {
                        // No formula found, return existing token
                        token.deinit();
                        token = fresh_token;
                    }
                } else {
                    // Token was already refreshed by another process
                    token.deinit();
                    token = fresh_token;
                }
            }
        }

        try outputToken(stdout, key, token, json_output);
    } else if (std.mem.eql(u8, action, "list")) {
        const keys = try listTokenFiles(allocator, storage_path);
        defer {
            for (keys) |k| allocator.free(k);
            allocator.free(keys);
        }

        // Filter keys
        var filtered: std.ArrayListUnmanaged([]const u8) = .{};
        defer filtered.deinit(allocator);

        for (keys) |k| {
            // If --key is provided, use it as prefix filter
            if (key_arg) |prefix| {
                if (!std.mem.startsWith(u8, k, prefix)) continue;
            }
            if (keyMatchesFilter(k, formula_filter, method_filter, identity_filter)) {
                try filtered.append(allocator, k);
            }
        }

        if (json_output) {
            try stdout.print("[\n", .{});
            for (filtered.items, 0..) |k, idx| {
                const parsed = parseStorageKey(k);
                try stdout.print("  {{\n", .{});
                try stdout.print("    \"key\": \"{s}\",\n", .{k});
                try stdout.print("    \"formula\": \"{s}\"", .{parsed.formula});
                if (parsed.method) |m| {
                    try stdout.print(",\n    \"method\": \"{s}\"", .{m});
                }
                if (parsed.identity) |i| {
                    try stdout.print(",\n    \"identity\": \"{s}\"", .{i});
                }
                try stdout.print("\n  }}", .{});
                if (idx < filtered.items.len - 1) try stdout.print(",", .{});
                try stdout.print("\n", .{});
            }
            try stdout.print("]\n", .{});
        } else {
            if (filtered.items.len == 0) {
                try stdout.print("No tokens found\n", .{});
            } else {
                try stdout.print("Stored tokens:\n", .{});
                for (filtered.items) |k| {
                    const parsed = parseStorageKey(k);
                    try stdout.print("  {s}", .{k});
                    if (parsed.identity) |i| {
                        try stdout.print(" (identity: {s})", .{i});
                    }
                    try stdout.print("\n", .{});
                }
            }
        }
    } else if (std.mem.eql(u8, action, "delete")) {
        var key: []const u8 = undefined;
        var key_owned = false;

        if (key_arg) |k| {
            key = k;
        } else if (formula_filter != null) {
            key = try buildStorageKey(allocator, formula_filter.?, method_filter, identity_filter);
            key_owned = true;
        } else {
            try stderr.print("Error: Either --key or --formula is required for 'delete'\n", .{});
            return error.MissingArguments;
        }
        defer if (key_owned) allocator.free(key);

        try storage.storage().delete(key);
        if (!json_output) {
            try stdout.print("Token deleted: {s}\n", .{key});
        } else {
            try stdout.print("{{\"deleted\": \"{s}\"}}\n", .{key});
        }
    } else {
        try stderr.print("Error: Unknown action '{s}'. Use: get, list, delete\n", .{action});
        return error.InvalidParameter;
    }
}

// Tests

test "storageKeyFromFormula generates conventional key" {
    const allocator = std.testing.allocator;

    const v2_json =
        \\{
        \\  "schema": "v2",
        \\  "id": "acme",
        \\  "label": "Acme API",
        \\  "methods": {
        \\    "api_key": {
        \\      "script": [
        \\        { "type": "copy_key", "note": "Paste your API key" }
        \\      ]
        \\    }
        \\  },
        \\  "apis": {
        \\    "rest": {
        \\      "base_url": "https://api.acme.com",
        \\      "auth_header": "Authorization: Bearer {token}",
        \\      "methods": ["api_key"]
        \\    }
        \\  }
        \\}
    ;

    var formula_owned = try formulas.loadFromJsonSlice(allocator, v2_json);
    defer formula_owned.deinit();

    const key = try storageKeyFromFormula(allocator, formula_owned.asConst(), "api_key", null);
    defer allocator.free(key);
    try std.testing.expectEqualStrings("acme:api_key", key);
}

test "storageKeyFromFormula includes identity" {
    const allocator = std.testing.allocator;

    const v2_json =
        \\{
        \\  "schema": "v2",
        \\  "id": "linear",
        \\  "label": "Linear",
        \\  "identity": {
        \\    "label": "Workspace",
        \\    "hint": "Use the workspace slug"
        \\  },
        \\  "methods": {
        \\    "oauth": {
        \\      "endpoints": {
        \\        "authorize": "https://linear.app/oauth/authorize",
        \\        "token": "https://api.linear.app/oauth/token"
        \\      }
        \\    }
        \\  },
        \\  "apis": {
        \\    "graphql": {
        \\      "base_url": "https://api.linear.app/graphql",
        \\      "auth_header": "Authorization: {token}",
        \\      "methods": ["oauth"]
        \\    }
        \\  }
        \\}
    ;

    var formula_owned = try formulas.loadFromJsonSlice(allocator, v2_json);
    defer formula_owned.deinit();

    const key = try storageKeyFromFormula(allocator, formula_owned.asConst(), "oauth", "acme");
    defer allocator.free(key);
    try std.testing.expectEqualStrings("linear:oauth:acme", key);
}

test "tokenFromCredential sets method name as token type" {
    const allocator = std.testing.allocator;

    var token = try tokenFromCredential(allocator, "api_key", "secret123");
    defer token.deinit();

    try std.testing.expectEqualStrings("api_key", token.token_type);
    try std.testing.expectEqualStrings("secret123", token.access_token);
}
