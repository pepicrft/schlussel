//! Command-line interface for Schlussel OAuth operations
//!
//! ## Usage
//!
//! ```bash
//! # Generate an interaction plan from a formula
//! schlussel plan github
//!
//! # Device Code Flow with preset provider
//! schlussel device github --client-id <id> --scope "repo user"
//!
//! # Device Code Flow with custom provider
//! schlussel device --custom-provider \
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
const formulas = @import("formulas.zig");
const callback = @import("callback.zig");
const pkce = @import("pkce.zig");

const FormulaPlan = struct {
    id: []const u8,
    label: []const u8,
    methods: []const formulas.Method,
    interaction: ?formulas.Interaction,
};

const InteractionPlan = struct {
    method: formulas.Method,
    steps: []const formulas.InteractionStep,
    context: ?InteractionContext,
};

const PlanOutput = struct {
    id: []const u8,
    label: []const u8,
    methods: []const formulas.Method,
    interaction: ?formulas.Interaction,
    plan: ?InteractionPlan,
};

const InteractionContext = struct {
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

const ResolvedPlanOwned = struct {
    allocator: Allocator,
    steps: []const formulas.InteractionStep,
    context: InteractionContext,
    allocations: std.ArrayListUnmanaged([]const u8),

    fn deinit(self: *ResolvedPlanOwned) void {
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

fn expandInteractionSteps(
    allocator: Allocator,
    steps: []const formulas.InteractionStep,
    replacements: []const Replacement,
    context: InteractionContext,
    allocations: *std.ArrayListUnmanaged([]const u8),
) !ResolvedPlanOwned {
    const steps_out = try allocator.alloc(formulas.InteractionStep, steps.len);
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
            .@"type" = step.@"type",
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

fn resolveInteractionSteps(
    allocator: Allocator,
    formula: *const formulas.Formula,
    method: formulas.Method,
    client_id_override: ?[]const u8,
    client_secret_override: ?[]const u8,
    scope_override: ?[]const u8,
    redirect_uri: []const u8,
) !ResolvedPlanOwned {
    const default_device_steps = [_]formulas.InteractionStep{
        .{ .@"type" = "open_url", .value = "{verification_uri}", .note = null },
        .{ .@"type" = "enter_code", .value = "{user_code}", .note = null },
        .{ .@"type" = "wait_for_token", .value = null, .note = null },
    };
    const default_code_steps = [_]formulas.InteractionStep{
        .{ .@"type" = "open_url", .value = "{authorize_url}", .note = null },
        .{ .@"type" = "wait_for_callback", .value = null, .note = null },
    };

    const steps_source = if (formula.interaction) |interaction|
        interaction.auth_steps orelse switch (method) {
            .device_code => default_device_steps[0..],
            .authorization_code => default_code_steps[0..],
        }
    else switch (method) {
        .device_code => default_device_steps[0..],
        .authorization_code => default_code_steps[0..],
    };

    var replacements: std.ArrayListUnmanaged(Replacement) = .{};
    defer replacements.deinit(allocator);

    var allocations: std.ArrayListUnmanaged([]const u8) = .{};
    errdefer {
        for (allocations.items) |item| {
            allocator.free(item);
        }
        allocations.deinit(allocator);
    }

    var context = InteractionContext{};

    switch (method) {
        .authorization_code => {
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
        },
        .device_code => {
            var config = try oauth.configFromFormula(
                allocator,
                formula,
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
        },
    }

    return expandInteractionSteps(allocator, steps_source, replacements.items, context, &allocations);
}

fn cmdRun(allocator: Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !void {
    if (args.len < 3) {
        try stderr.print("Error: Missing provider name\n\n", .{});
        try stderr.print("USAGE:\n    schlussel run <provider> [options]\n\n", .{});
        try stderr.print("OPTIONS:\n", .{});
        try stderr.print("    --plan-json <path|- >         Resolved plan JSON from `schlussel plan --resolve`\n", .{});
        try stderr.print("    --formula-json <path>         Load a declarative formula JSON\n", .{});
        try stderr.print("    --client-id <id>              OAuth client ID override\n", .{});
        try stderr.print("    --client-secret <secret>      OAuth client secret override\n", .{});
        try stderr.print("    --scope <scopes>              OAuth scopes (space-separated)\n", .{});
        try stderr.print("    --open-browser <true|false>   Open the authorization URL (default: true)\n", .{});
        try stderr.print("\n", .{});
        return error.MissingArguments;
    }

    const provider_arg = args[2];

    var plan_json_path: ?[]const u8 = null;
    var formula_json_path: ?[]const u8 = null;
    var client_id_override: ?[]const u8 = null;
    var client_secret_override: ?[]const u8 = null;
    var scope_override: ?[]const u8 = null;
    var open_browser = true;

    var i: usize = 3;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (i + 1 >= args.len) {
            try stderr.print("Error: Missing value for option '{s}'\n", .{arg});
            return error.MissingOptionValue;
        }

        if (std.mem.eql(u8, arg, "--plan-json")) {
            plan_json_path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--formula-json")) {
            formula_json_path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--client-id")) {
            client_id_override = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--client-secret")) {
            client_secret_override = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--scope")) {
            scope_override = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--open-browser")) {
            const value = args[i + 1];
            if (std.mem.eql(u8, value, "true")) {
                open_browser = true;
            } else if (std.mem.eql(u8, value, "false")) {
                open_browser = false;
            } else {
                try stderr.print("Error: --open-browser must be true or false\n", .{});
                return error.InvalidParameter;
            }
            i += 1;
        } else {
            try stderr.print("Error: Unknown option '{s}'\n", .{arg});
            return error.UnknownOption;
        }
    }

    if (plan_json_path == null) {
        try stderr.print("Error: --plan-json is required\n", .{});
        return error.MissingArguments;
    }

    var plan_bytes: []const u8 = undefined;
    if (std.mem.eql(u8, plan_json_path.?, "-")) {
        const stdin_file = std.fs.File.stdin();
        plan_bytes = try stdin_file.readToEndAlloc(allocator, 1024 * 1024);
    } else {
        const plan_file = try std.fs.cwd().openFile(plan_json_path.?, .{});
        defer plan_file.close();
        plan_bytes = try plan_file.readToEndAlloc(allocator, 1024 * 1024);
    }
    defer allocator.free(plan_bytes);

    const plan_parsed = try std.json.parseFromSlice(PlanOutput, allocator, plan_bytes, .{ .allocate = .alloc_always });
    defer plan_parsed.deinit();

    const plan_value = plan_parsed.value.plan orelse {
        try stderr.print("Error: plan JSON missing resolved plan data\n", .{});
        return error.InvalidParameter;
    };
    const context = plan_value.context orelse {
        try stderr.print("Error: plan JSON missing context\n", .{});
        return error.InvalidParameter;
    };

    var thirdPartyFormula: ?formulas.FormulaOwned = null;
    defer if (thirdPartyFormula) |*owner| owner.deinit();

    if (formula_json_path != null) {
        thirdPartyFormula = try formulas.loadFromPath(allocator, formula_json_path.?);
    }

    var formula_ptr: ?*const formulas.Formula = null;
    if (thirdPartyFormula) |owner| {
        if (!std.mem.eql(u8, owner.formula.id, provider_arg)) {
            try stderr.print(
                "Warning: formula id '{s}' does not match provider '{s}'\n",
                .{ owner.formula.id, provider_arg },
            );
        }
        formula_ptr = owner.asConst();
    } else {
        formula_ptr = try formulas.findById(allocator, provider_arg);
    }

    const formula = formula_ptr orelse {
        try stderr.print("Error: Unknown provider '{s}'\n", .{provider_arg});
        return error.UnknownProvider;
    };

    const redirect_uri = context.redirect_uri orelse "http://127.0.0.1:0/callback";
    var owned_config = oauth.configFromFormula(
        allocator,
        formula,
        client_id_override,
        client_secret_override,
        redirect_uri,
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

    var token: session.Token = undefined;

    switch (plan_value.method) {
        .device_code => {
            const device_code = context.device_code orelse {
                try stderr.print("Error: plan context missing device_code\n", .{});
                return error.InvalidParameter;
            };
            const interval = context.interval orelse 5;
            token = client.pollDeviceCode(device_code, interval, context.expires_in) catch |err| {
                try stderr.print("\nAuthorization failed: {s}\n", .{@errorName(err)});
                return err;
            };
        },
        .authorization_code => {
            const authorize_url = context.authorize_url orelse {
                try stderr.print("Error: plan context missing authorize_url\n", .{});
                return error.InvalidParameter;
            };
            const pkce_verifier = context.pkce_verifier orelse {
                try stderr.print("Error: plan context missing pkce_verifier\n", .{});
                return error.InvalidParameter;
            };
            const state = context.state orelse {
                try stderr.print("Error: plan context missing state\n", .{});
                return error.InvalidParameter;
            };
            const callback_uri = context.redirect_uri orelse {
                try stderr.print("Error: plan context missing redirect_uri\n", .{});
                return error.InvalidParameter;
            };

            const port = try parseRedirectPort(callback_uri);
            var server = try callback.CallbackServer.init(allocator, port);
            defer server.deinit();

            if (open_browser) {
                try stdout.print("\nOpening browser for authorization...\n", .{});
                try stdout.print("If the browser doesn't open, visit:\n{s}\n\n", .{authorize_url});
                callback.openBrowser(authorize_url) catch {};
            } else {
                try stdout.print("\nVisit the following URL to authorize:\n{s}\n\n", .{authorize_url});
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
        },
    }
    defer token.deinit();

    try stdout.print("\n=== Authorization Successful! ===\n\n", .{});
    try stdout.print("Token type: {s}\n", .{token.token_type});
    if (token.scope) |s| {
        try stdout.print("Scope: {s}\n", .{s});
    }
    if (token.expires_at) |expires_at| {
        try stdout.print("Expires at: {d} (Unix timestamp)\n", .{expires_at});
    }

    try client.saveToken(provider_arg, token);
    try stdout.print("\nToken saved with key: {s}\n", .{provider_arg});
}

const Command = enum {
    plan,
    run,
    device,
    code,
    token,
    register,
    register_read,
    register_update,
    register_delete,
    help,

    pub fn fromString(str: []const u8) ?Command {
        const eql = std.mem.eql;
        if (eql(u8, str, "plan")) return .plan;
        if (eql(u8, str, "run")) return .run;
        if (eql(u8, str, "device")) return .device;
        if (eql(u8, str, "code")) return .code;
        if (eql(u8, str, "token")) return .token;
        if (eql(u8, str, "register")) return .register;
        if (eql(u8, str, "register-read")) return .register_read;
        if (eql(u8, str, "register-update")) return .register_update;
        if (eql(u8, str, "register-delete")) return .register_delete;
        if (eql(u8, str, "help")) return .help;
        return null;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Clean up builtin formulas on exit
    defer formulas.deinitBuiltinFormulas();

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
        .plan => try cmdPlan(allocator, args, stdout, stderr),
        .run => try cmdRun(allocator, args, stdout, stderr),
        .device => try cmdDevice(allocator, args, stdout, stderr),
        .code => try cmdCode(allocator, args, stdout, stderr),
        .token => try cmdToken(allocator, args, stdout, stderr),
        .register => try cmdRegister(allocator, args, stdout, stderr),
        .register_read => try cmdRegisterRead(allocator, args, stdout, stderr),
        .register_update => try cmdRegisterUpdate(allocator, args, stdout, stderr),
        .register_delete => try cmdRegisterDelete(allocator, args, stdout, stderr),
        .help => {}, // already handled
    }
}

fn printUsage(writer: anytype) !void {
    try writer.writeAll(
        \\Schlussel Auth Command-Line Tool
        \\
        \\USAGE:
        \\    schlussel <command> [options]
        \\
        \\COMMANDS:
        \\    plan                Emit an interaction plan for a provider
        \\    run                 Execute a resolved interaction plan
        \\    device              Device Code Flow authentication
        \\    code                Authorization Code Flow with PKCE
        \\    token <action>      Token management operations
        \\    register            Dynamically register OAuth client
        \\    register-read       Read dynamic client configuration
        \\    register-update     Update dynamic client configuration
        \\    register-delete     Delete dynamic client registration
        \\    help                Show this help message
        \\
        \\TOKEN ACTIONS:
        \\    get                 Retrieve a stored token
        \\    list                List all stored tokens
        \\    delete              Delete a stored token
        \\
        \\EXAMPLES:
        \\    # Emit a JSON interaction plan
        \\    schlussel plan github
        \\
        \\    # Emit a JSON interaction plan from a custom formula
        \\    schlussel plan acme --formula-json ~/formulas/acme.json
        \\
        \\    # Execute a resolved interaction plan
        \\    schlussel run github --plan-json plan.json
        \\
        \\    # Device Code Flow with GitHub
        \\    schlussel device github --client-id <id> --scope "repo user"
        \\
        \\    # Device Code Flow with a formula JSON
        \\    schlussel device slack --formula-json ~/formulas/slack.json --client-id <id>
        \\
        \\    # Register a new OAuth client
        \\    schlussel register https://auth.example.com/register \
        \\      --client-name "My App" \
        \\      --redirect-uri https://example.com/callback \
        \\      --grant-types authorization_code,refresh_token
        \\
        \\    # Read an existing registration (use registration_client_uri)
        \\    schlussel register-read https://auth.example.com/register/abc \
        \\      --registration-access-token <token>
        \\
        \\For more help, visit: https://github.com/pepicrft/schlussel
        \\
    );
}

fn cmdPlan(allocator: Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !void {
    if (args.len < 3) {
        try stderr.print("Error: Missing provider name\n\n", .{});
        try stderr.print("USAGE:\n    schlussel plan <provider> [options]\n\n", .{});
        try stderr.print("OPTIONS:\n", .{});
        try stderr.print("    --formula-json <path>         Load a declarative formula JSON\n", .{});
        try stderr.print("    --method <name>               Filter to a single method\n", .{});
        try stderr.print("    --client-id <id>              OAuth client ID override\n", .{});
        try stderr.print("    --client-secret <secret>      OAuth client secret override\n", .{});
        try stderr.print("    --scope <scopes>              OAuth scopes (space-separated)\n", .{});
        try stderr.print("    --redirect-uri <uri>          Redirect URI (default: http://127.0.0.1/callback)\n", .{});
        try stderr.print("    --resolve                      Resolve placeholders into concrete steps\n", .{});
        return error.MissingArguments;
    }

    const provider_arg = args[2];
    var formula_json_path: ?[]const u8 = null;
    var method_filter: ?[]const u8 = null;
    var client_id_override: ?[]const u8 = null;
    var client_secret_override: ?[]const u8 = null;
    var scope_override: ?[]const u8 = null;
    var redirect_uri: []const u8 = "http://127.0.0.1:0/callback";
    var resolve_plan = false;

    var i: usize = 3;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (i + 1 >= args.len) {
            try stderr.print("Error: Missing value for option '{s}'\n", .{arg});
            return error.MissingOptionValue;
        }

        if (std.mem.eql(u8, arg, "--formula-json")) {
            formula_json_path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--method")) {
            method_filter = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--client-id")) {
            client_id_override = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--client-secret")) {
            client_secret_override = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--scope")) {
            scope_override = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--redirect-uri")) {
            redirect_uri = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--resolve")) {
            resolve_plan = true;
        } else {
            try stderr.print("Error: Unknown option '{s}'\n", .{arg});
            return error.UnknownOption;
        }
    }

    var thirdPartyFormula: ?formulas.FormulaOwned = null;
    defer if (thirdPartyFormula) |*owner| owner.deinit();

    var formula_ptr: ?*const formulas.Formula = null;
    if (formula_json_path != null) {
        thirdPartyFormula = try formulas.loadFromPath(allocator, formula_json_path.?);
        const owner = thirdPartyFormula.?;
        if (!std.mem.eql(u8, owner.formula.id, provider_arg)) {
            try stderr.print(
                "Warning: formula id '{s}' does not match provider '{s}'\n",
                .{ owner.formula.id, provider_arg },
            );
        }
        formula_ptr = owner.asConst();
    } else {
        formula_ptr = try formulas.findById(allocator, provider_arg);
    }

    const formula = formula_ptr orelse {
        try stderr.print("Error: Unknown provider '{s}'\n", .{provider_arg});
        return error.UnknownProvider;
    };

    var methods = formula.methods;
    var single_method: [1]formulas.Method = undefined;
    var selected_method: ?formulas.Method = null;
    if (method_filter) |method_name| {
        const method = formulas.methodFromString(method_name) orelse {
            try stderr.print("Error: Unknown method '{s}'\n", .{method_name});
            return error.InvalidMethod;
        };
        var found = false;
        for (formula.methods) |item| {
            if (item == method) {
                found = true;
                break;
            }
        }
        if (!found) {
            try stderr.print("Error: Method '{s}' not supported by provider '{s}'\n", .{ method_name, formula.id });
            return error.UnsupportedOperation;
        }
        single_method[0] = method;
        methods = single_method[0..];
        selected_method = method;
    } else if (formula.methods.len == 1) {
        selected_method = formula.methods[0];
    }

    var resolved_steps: ?ResolvedPlanOwned = null;
    defer if (resolved_steps) |*owned| owned.deinit();

    var plan_data: ?InteractionPlan = null;
    if (resolve_plan) {
        const method = selected_method orelse {
            try stderr.print("Error: --method is required to resolve a plan\n", .{});
            return error.MissingArguments;
        };

        resolved_steps = try resolveInteractionSteps(
            allocator,
            formula,
            method,
            client_id_override,
            client_secret_override,
            scope_override,
            redirect_uri,
        );
        plan_data = InteractionPlan{
            .method = method,
            .steps = resolved_steps.?.steps,
            .context = resolved_steps.?.context,
        };
    }

    const output = PlanOutput{
        .id = formula.id,
        .label = formula.label,
        .methods = methods,
        .interaction = formula.interaction,
        .plan = plan_data,
    };

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();
    try std.json.Stringify.value(output, .{ .whitespace = .indent_2 }, &out.writer);
    try stdout.print("{s}\n", .{out.written()});
}

fn cmdDevice(allocator: Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !void {
    if (args.len < 3) {
        try stderr.print("Error: Missing provider name or --custom-provider flag\n\n", .{});
        try stderr.print("USAGE:\n    schlussel device <provider|--custom-provider> [options]\n\n", .{});
        try stderr.print("PROVIDERS:\n    github, google, microsoft, gitlab, tuist\n\n", .{});
        try stderr.print("OPTIONS:\n", .{});
        try stderr.print("    --client-id <id>              OAuth client ID (optional if formula provides one)\n", .{});
        try stderr.print("    --client-secret <secret>      OAuth client secret (optional)\n", .{});
        try stderr.print("    --scope <scopes>              OAuth scopes (space-separated)\n", .{});
        try stderr.print("    --formula-json <path>         Load a declarative formula JSON\n", .{});
        try stderr.print("\n", .{});
        try stderr.print("CUSTOM PROVIDER OPTIONS:\n", .{});
        try stderr.print("    --device-code-endpoint <url>  Device authorization endpoint\n", .{});
        try stderr.print("    --token-endpoint <url>        Token endpoint\n", .{});
        try stderr.print("    --authorization-endpoint <url> Authorization endpoint (optional)\n", .{});
        try stderr.print("    --redirect-uri <uri>         Redirect URI (default: http://127.0.0.1/callback)\n", .{});
        return error.MissingArguments;
    }

    const provider_arg = args[2];
    const is_custom = std.mem.eql(u8, provider_arg, "--custom-provider");

    var thirdPartyFormula: ?formulas.FormulaOwned = null;
    defer if (thirdPartyFormula) |*owner| owner.deinit();

    // We need owned_config at function scope so it lives long enough
    var owned_config: ?oauth.OAuthConfigOwned = null;
    defer if (owned_config) |*oc| oc.deinit();

    var config: oauth.OAuthConfig = undefined;

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

        owned_config = oauth.OAuthConfigOwned{
            .allocator = allocator,
            .client_id = try allocator.dupe(u8, client_id.?),
            .client_secret = if (client_secret) |s| try allocator.dupe(u8, s) else null,
            .authorization_endpoint = try allocator.dupe(u8, authorization_endpoint orelse "https://example.com/oauth/authorize"),
            .token_endpoint = try allocator.dupe(u8, token_endpoint.?),
            .redirect_uri = try allocator.dupe(u8, redirect_uri.?),
            .scope = if (scope) |s| try allocator.dupe(u8, s) else null,
            .device_authorization_endpoint = if (device_code_endpoint) |e| try allocator.dupe(u8, e) else null,
        };

        config = owned_config.?.toConfig();
    } else {
        var client_id: ?[]const u8 = null;
        var scope: ?[]const u8 = null;
        var redirect_uri: ?[]const u8 = null;
        var client_secret: ?[]const u8 = null;
        var formula_json_path: ?[]const u8 = null;

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
            } else if (std.mem.eql(u8, arg, "--redirect-uri")) {
                redirect_uri = args[i + 1];
                i += 1;
            } else if (std.mem.eql(u8, arg, "--client-secret")) {
                client_secret = args[i + 1];
                i += 1;
            } else if (std.mem.eql(u8, arg, "--formula-json")) {
                formula_json_path = args[i + 1];
                i += 1;
            } else {
                try stderr.print("Error: Unknown option '{s}'\n", .{arg});
                return error.UnknownOption;
            }
        }

        if (formula_json_path != null) {
            thirdPartyFormula = try formulas.loadFromPath(allocator, formula_json_path.?);
        }

        var formula_ptr: ?*const formulas.Formula = null;
        if (thirdPartyFormula) |owner| {
            if (!std.mem.eql(u8, owner.formula.id, provider_arg)) {
                try stderr.print(
                    "Warning: formula id '{s}' does not match provider '{s}'\n",
                    .{ owner.formula.id, provider_arg },
                );
            }
            formula_ptr = owner.asConst();
        } else {
            formula_ptr = try formulas.findById(allocator, provider_arg);
        }

        if (formula_ptr) |formula| {
            const redirect = redirect_uri orelse "http://127.0.0.1/callback";
            owned_config = oauth.configFromFormula(
                allocator,
                formula,
                client_id,
                client_secret,
                redirect,
                scope,
            ) catch |err| {
                if (err == error.MissingClientId) {
                    try stderr.print("Error: --client-id is required (formula does not provide one)\n", .{});
                    return error.MissingRequiredOptions;
                }
                return err;
            };
            config = owned_config.?.toConfig();
        } else {
            if (client_id == null) {
                try stderr.print("Error: --client-id is required\n", .{});
                return error.MissingRequiredOptions;
            }
            const preset_scope = scope orelse "repo user";
            config = try createPresetConfig(provider_arg, client_id.?, preset_scope);
        }
    }

    // Create storage (default to file storage)
    var storage = try session.FileStorage.init(allocator, "schlussel");
    defer storage.deinit();

    // Create OAuth client
    var client = oauth.OAuthClient.init(allocator, config, storage.storage());
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

fn cmdCode(allocator: Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !void {
    if (args.len < 3) {
        try stderr.print("Error: Missing provider name\n\n", .{});
        try stderr.print("USAGE:\n    schlussel code <provider> [options]\n\n", .{});
        try stderr.print("PROVIDERS:\n    tuist, github, google, microsoft, gitlab\n\n", .{});
        try stderr.print("OPTIONS:\n", .{});
        try stderr.print("    --client-id <id>              OAuth client ID (optional if formula provides one)\n", .{});
        try stderr.print("    --client-secret <secret>      OAuth client secret (optional)\n", .{});
        try stderr.print("    --scope <scopes>              OAuth scopes (space-separated)\n", .{});
        try stderr.print("    --redirect-uri <uri>          Redirect URI (default: auto-assigned)\n", .{});
        try stderr.print("    --formula-json <path>         Load a declarative formula JSON\n", .{});
        try stderr.print("\n", .{});
        return error.MissingArguments;
    }

    const provider_arg = args[2];

    var client_id: ?[]const u8 = null;
    var scope: ?[]const u8 = null;
    var redirect_uri: ?[]const u8 = null;
    var client_secret: ?[]const u8 = null;
    var formula_json_path: ?[]const u8 = null;

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
        } else if (std.mem.eql(u8, arg, "--redirect-uri")) {
            redirect_uri = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--client-secret")) {
            client_secret = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--formula-json")) {
            formula_json_path = args[i + 1];
            i += 1;
        } else {
            try stderr.print("Error: Unknown option '{s}'\n", .{arg});
            return error.UnknownOption;
        }
    }

    var thirdPartyFormula: ?formulas.FormulaOwned = null;
    defer if (thirdPartyFormula) |*owner| owner.deinit();

    // We need owned_config at function scope so it lives long enough
    var owned_config: ?oauth.OAuthConfigOwned = null;
    defer if (owned_config) |*oc| oc.deinit();

    if (formula_json_path != null) {
        thirdPartyFormula = try formulas.loadFromPath(allocator, formula_json_path.?);
    }

    var formula_ptr: ?*const formulas.Formula = null;
    if (thirdPartyFormula) |owner| {
        if (!std.mem.eql(u8, owner.formula.id, provider_arg)) {
            try stderr.print(
                "Warning: formula id '{s}' does not match provider '{s}'\n",
                .{ owner.formula.id, provider_arg },
            );
        }
        formula_ptr = owner.asConst();
    } else {
        formula_ptr = try formulas.findById(allocator, provider_arg);
    }

    var config: oauth.OAuthConfig = undefined;

    if (formula_ptr) |formula| {
        // For authorization code flow, we'll use a dynamic redirect URI from the callback server
        const redirect = redirect_uri orelse "http://127.0.0.1:0/callback";
        owned_config = oauth.configFromFormula(
            allocator,
            formula,
            client_id,
            client_secret,
            redirect,
            scope,
        ) catch |err| {
            if (err == error.MissingClientId) {
                try stderr.print("Error: --client-id is required (formula does not provide one)\n", .{});
                return error.MissingRequiredOptions;
            }
            return err;
        };
        config = owned_config.?.toConfig();
    } else {
        if (client_id == null) {
            try stderr.print("Error: --client-id is required\n", .{});
            return error.MissingRequiredOptions;
        }
        const preset_scope = scope orelse "openid";
        config = try createPresetConfig(provider_arg, client_id.?, preset_scope);
    }

    // Create storage (default to file storage)
    var storage = try session.FileStorage.init(allocator, "schlussel");
    defer storage.deinit();

    // Create OAuth client
    var client = oauth.OAuthClient.init(allocator, config, storage.storage());
    defer client.deinit();

    try stdout.print("\n=== Authorization Code Flow with PKCE ===\n\n", .{});
    try stdout.print("Starting authorization...\n", .{});

    // Perform Authorization Code Flow
    var token = client.authorize() catch |err| {
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
    try client.saveToken(provider_arg, token);
    try stdout.print("\nToken saved with key: {s}\n", .{provider_arg});
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

const RegistrationOptions = struct {
    metadata: registration.ClientMetadata,
    redirect_uris_list: std.ArrayList([]const u8),
    grant_types_list: std.ArrayList([]const u8),
    response_types_list: std.ArrayList([]const u8),
    access_token: ?[]const u8 = null,

    fn deinit(self: *RegistrationOptions, allocator: Allocator) void {
        self.metadata.deinit();
        for (self.redirect_uris_list.items) |uri| allocator.free(uri);
        self.redirect_uris_list.deinit(allocator);
        for (self.grant_types_list.items) |gt| allocator.free(gt);
        self.grant_types_list.deinit(allocator);
        for (self.response_types_list.items) |rt| allocator.free(rt);
        self.response_types_list.deinit(allocator);
    }
};

fn appendCommaSeparated(allocator: Allocator, list: *std.ArrayList([]const u8), value: []const u8) !void {
    var iter = std.mem.splitScalar(u8, value, ',');
    while (iter.next()) |item| {
        const trimmed = std.mem.trim(u8, item, " ");
        if (trimmed.len > 0) {
            try list.append(allocator, try allocator.dupe(u8, trimmed));
        }
    }
}

fn parseRegistrationOptions(
    allocator: Allocator,
    args: []const []const u8,
    start_index: usize,
    stderr: anytype,
    require_redirect_uris: bool,
    require_access_token: bool,
) !RegistrationOptions {
    var client_name: ?[]const u8 = null;
    var redirect_uris_list: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (redirect_uris_list.items) |uri| allocator.free(uri);
        redirect_uris_list.deinit(allocator);
    }

    var grant_types_list: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (grant_types_list.items) |gt| allocator.free(gt);
        grant_types_list.deinit(allocator);
    }

    var response_types_list: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (response_types_list.items) |rt| allocator.free(rt);
        response_types_list.deinit(allocator);
    }

    var scope: ?[]const u8 = null;
    var token_auth_method: ?[]const u8 = null;
    var access_token: ?[]const u8 = null;

    var i: usize = start_index;
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
            try appendCommaSeparated(allocator, &grant_types_list, args[i + 1]);
            i += 1;
        } else if (std.mem.eql(u8, arg, "--response-types")) {
            try appendCommaSeparated(allocator, &response_types_list, args[i + 1]);
            i += 1;
        } else if (std.mem.eql(u8, arg, "--scope")) {
            scope = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--token-auth-method")) {
            token_auth_method = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--registration-access-token")) {
            access_token = args[i + 1];
            i += 1;
        } else {
            try stderr.print("Error: Unknown option '{s}'\n", .{arg});
            return error.UnknownOption;
        }
    }

    if (require_redirect_uris and redirect_uris_list.items.len == 0) {
        try stderr.print("Error: At least one --redirect-uri is required\n", .{});
        return error.MissingRequiredOptions;
    }

    if (require_access_token and access_token == null) {
        try stderr.print("Error: --registration-access-token is required\n", .{});
        return error.MissingRequiredOptions;
    }

    var metadata = try registration.ClientMetadata.init(allocator);
    errdefer metadata.deinit();

    if (client_name) |name| metadata.client_name = name;
    metadata.redirect_uris = redirect_uris_list.items;
    if (grant_types_list.items.len > 0) {
        metadata.grant_types = grant_types_list.items;
    }
    if (response_types_list.items.len > 0) {
        metadata.response_types = response_types_list.items;
    }
    if (scope) |s| {
        metadata.scope = try allocator.dupe(u8, s);
    }
    if (token_auth_method) |m| {
        metadata.token_endpoint_auth_method = try allocator.dupe(u8, m);
    }

    return .{
        .metadata = metadata,
        .redirect_uris_list = redirect_uris_list,
        .grant_types_list = grant_types_list,
        .response_types_list = response_types_list,
        .access_token = access_token,
    };
}

fn parseRegistrationAccessToken(args: []const []const u8, start_index: usize, stderr: anytype) ![]const u8 {
    var access_token: ?[]const u8 = null;

    var i: usize = start_index;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (i + 1 >= args.len) {
            try stderr.print("Error: Missing value for option '{s}'\n", .{arg});
            return error.MissingOptionValue;
        }

        if (std.mem.eql(u8, arg, "--registration-access-token")) {
            access_token = args[i + 1];
            i += 1;
        } else {
            try stderr.print("Error: Unknown option '{s}'\n", .{arg});
            return error.UnknownOption;
        }
    }

    if (access_token == null) {
        try stderr.print("Error: --registration-access-token is required\n", .{});
        return error.MissingRequiredOptions;
    }

    return access_token.?;
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

    var options = try parseRegistrationOptions(allocator, args, 3, stderr, true, false);
    defer options.deinit(allocator);

    // Create registration client
    var reg_client = try registration.DynamicRegistration.init(allocator, endpoint);
    defer reg_client.deinit();

    try stdout.print("\n=== Dynamic Client Registration ===\n\n", .{});
    try stdout.print("Registering client with: {s}\n\n", .{endpoint});

    // Register the client
    var response = reg_client.register(options.metadata) catch |err| {
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

fn cmdRegisterRead(allocator: Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !void {
    if (args.len < 3) {
        try stderr.print("Error: Missing registration client URI\n\n", .{});
        try stderr.print("USAGE:\n    schlussel register-read <registration-client-uri> --registration-access-token <token>\n\n", .{});
        return error.MissingArguments;
    }

    const endpoint = args[2];
    const access_token = try parseRegistrationAccessToken(args, 3, stderr);

    var reg_client = try registration.DynamicRegistration.init(allocator, endpoint);
    defer reg_client.deinit();

    try stdout.print("\n=== Dynamic Client Registration ===\n\n", .{});
    try stdout.print("Reading registration from: {s}\n\n", .{endpoint});

    var response = reg_client.read(access_token) catch |err| {
        try stderr.print("\nRegistration read failed: {s}\n", .{@errorName(err)});
        return err;
    };
    defer response.deinit();

    try stdout.print("=== Registration Details ===\n\n", .{});
    try stdout.print("Client ID: {s}\n", .{response.client_id});

    if (response.client_secret) |secret| {
        try stdout.print("Client Secret: {s}\n", .{secret});
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
}

fn cmdRegisterUpdate(allocator: Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !void {
    if (args.len < 3) {
        try stderr.print("Error: Missing registration client URI\n\n", .{});
        try stderr.print("USAGE:\n    schlussel register-update <registration-client-uri> [options]\n\n", .{});
        try stderr.print("OPTIONS:\n", .{});
        try stderr.print("    --registration-access-token <token>  Registration access token\n", .{});
        try stderr.print("    --client-name <name>                 Human-readable client name\n", .{});
        try stderr.print("    --redirect-uri <uri>                 Redirection URI (can be specified multiple times)\n", .{});
        try stderr.print("    --grant-types <types>                Comma-separated grant types\n", .{});
        try stderr.print("    --response-types <types>             Comma-separated response types\n", .{});
        try stderr.print("    --scope <scope>                      OAuth scope\n", .{});
        try stderr.print("    --token-auth-method <method>         Token endpoint auth method\n", .{});
        return error.MissingArguments;
    }

    const endpoint = args[2];

    var options = try parseRegistrationOptions(allocator, args, 3, stderr, false, true);
    defer options.deinit(allocator);

    const has_updates = options.redirect_uris_list.items.len > 0 or
        options.grant_types_list.items.len > 0 or
        options.response_types_list.items.len > 0 or
        options.metadata.client_name.len > 0 or
        options.metadata.scope != null or
        options.metadata.token_endpoint_auth_method != null;

    if (!has_updates) {
        try stderr.print("Error: No update fields provided\n", .{});
        return error.MissingRequiredOptions;
    }

    const access_token = options.access_token.?;

    var reg_client = try registration.DynamicRegistration.init(allocator, endpoint);
    defer reg_client.deinit();

    try stdout.print("\n=== Dynamic Client Registration ===\n\n", .{});
    try stdout.print("Updating registration at: {s}\n\n", .{endpoint});

    var response = reg_client.update(access_token, options.metadata) catch |err| {
        try stderr.print("\nRegistration update failed: {s}\n", .{@errorName(err)});
        return err;
    };
    defer response.deinit();

    try stdout.print("=== Update Successful ===\n\n", .{});
    try stdout.print("Client ID: {s}\n", .{response.client_id});
    if (response.registration_client_uri) |uri| {
        try stdout.print("Registration URI: {s}\n", .{uri});
    }
}

fn cmdRegisterDelete(allocator: Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !void {
    if (args.len < 3) {
        try stderr.print("Error: Missing registration client URI\n\n", .{});
        try stderr.print("USAGE:\n    schlussel register-delete <registration-client-uri> --registration-access-token <token>\n\n", .{});
        return error.MissingArguments;
    }

    const endpoint = args[2];
    const access_token = try parseRegistrationAccessToken(args, 3, stderr);

    var reg_client = try registration.DynamicRegistration.init(allocator, endpoint);
    defer reg_client.deinit();

    reg_client.delete(access_token) catch |err| {
        try stderr.print("\nRegistration delete failed: {s}\n", .{@errorName(err)});
        return err;
    };

    try stdout.print("\n=== Registration Deleted ===\n", .{});
}
