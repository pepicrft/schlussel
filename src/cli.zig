//! Command-line interface for Schlussel OAuth operations
//!
//! ## Usage
//!
//! ```bash
//! # Generate a script from a formula
//! schlussel script github
//!
//! # Resolve and execute directly
//! schlussel run github --method device_code
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
    script: ?formulas.Script,
    storage: ?formulas.StorageHints,
};

const ScriptOutput = struct {
    id: []const u8,
    label: []const u8,
    methods: []const formulas.Method,
    script: ?formulas.Script,
    storage: ?formulas.StorageHints,
    method: ?formulas.Method,
    context: ?ScriptContext,
};

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
    method: formulas.Method,
    token: TokenOutput,
};

const formula_schema_v1 =
    \\{
    \\  "$schema": "https://json-schema.org/draft/2020-12/schema",
    \\  "title": "Schlussel Formula v1",
    \\  "type": "object",
    \\  "required": ["schema", "id", "label", "methods"],
    \\  "properties": {
    \\    "schema": { "const": "v1" },
    \\    "id": { "type": "string" },
    \\    "label": { "type": "string" },
    \\    "methods": {
    \\      "type": "array",
    \\      "minItems": 1,
    \\      "items": {
    \\        "enum": [
    \\          "authorization_code",
    \\          "device_code",
    \\          "api_key",
    \\          "personal_access_token"
    \\        ]
    \\      }
    \\    },
    \\    "endpoints": {
    \\      "type": "object",
    \\      "properties": {
    \\        "authorize": { "type": "string" },
    \\        "token": { "type": "string" },
    \\        "device": { "type": "string" }
    \\      },
    \\      "additionalProperties": false
    \\    },
    \\    "scope": { "type": "string" },
    \\    "public_clients": {
    \\      "type": "array",
    \\      "items": {
    \\        "type": "object",
    \\        "required": ["name", "id"],
    \\        "properties": {
    \\          "name": { "type": "string" },
    \\          "id": { "type": "string" },
    \\          "secret": { "type": "string" },
    \\          "source": { "type": "string" },
    \\          "methods": {
    \\            "type": "array",
    \\            "items": { "type": "string" }
    \\          }
    \\        },
    \\        "additionalProperties": false
    \\      }
    \\    },
    \\    "script": {
    \\      "type": "object",
    \\      "properties": {
    \\        "register": {
    \\          "type": "object",
    \\          "required": ["url", "steps"],
    \\          "properties": {
    \\            "url": { "type": "string" },
    \\            "steps": { "type": "array", "items": { "type": "string" } }
    \\          },
    \\          "additionalProperties": false
    \\        },
    \\        "steps": {
    \\          "type": "array",
    \\          "items": {
    \\            "type": "object",
    \\            "required": ["type"],
    \\            "properties": {
    \\              "type": { "type": "string" },
    \\              "value": { "type": "string" },
    \\              "note": { "type": "string" }
    \\            },
    \\            "additionalProperties": false
    \\          }
    \\        }
    \\      },
    \\      "additionalProperties": false
    \\    },
    \\    "storage": {
    \\      "type": "object",
    \\      "properties": {
    \\        "key_template": { "type": "string" },
    \\        "label": { "type": "string" },
    \\        "value_label": { "type": "string" },
    \\        "identity_label": { "type": "string" },
    \\        "identity_hint": { "type": "string" },
    \\        "rotation_url": { "type": "string" },
    \\        "rotation_hint": { "type": "string" }
    \\      },
    \\      "additionalProperties": false
    \\    },
    \\    "quirks": {
    \\      "type": "object",
    \\      "properties": {
    \\        "dynamic_registration_endpoint": { "type": "string" },
    \\        "token_response": { "type": "string" },
    \\        "extra_response_fields": {
    \\          "type": "array",
    \\          "items": { "type": "string" }
    \\        },
    \\        "device_code_poll_endpoint": { "type": "string" },
    \\        "device_code_browser_url": { "type": "string" }
    \\      },
    \\      "additionalProperties": false
    \\    }
    \\  },
    \\  "additionalProperties": false
    \\}
;

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

fn resolveScriptSteps(
    allocator: Allocator,
    formula: *const formulas.Formula,
    method: formulas.Method,
    client_id_override: ?[]const u8,
    client_secret_override: ?[]const u8,
    scope_override: ?[]const u8,
    redirect_uri: []const u8,
) !ResolvedScript {
    const default_device_steps = [_]formulas.ScriptStep{
        .{ .@"type" = "open_url", .value = "{verification_uri}", .note = null },
        .{ .@"type" = "enter_code", .value = "{user_code}", .note = null },
        .{ .@"type" = "wait_for_token", .value = null, .note = null },
    };
    const default_code_steps = [_]formulas.ScriptStep{
        .{ .@"type" = "open_url", .value = "{authorize_url}", .note = null },
        .{ .@"type" = "wait_for_callback", .value = null, .note = null },
    };
    const default_api_key_steps = [_]formulas.ScriptStep{
        .{ .@"type" = "copy_key", .value = null, .note = "Paste your API key into the agent." },
    };

    const steps_source = if (formula.script) |script|
        script.steps orelse switch (method) {
            .device_code => default_device_steps[0..],
            .authorization_code => default_code_steps[0..],
            .api_key, .personal_access_token => default_api_key_steps[0..],
        }
    else switch (method) {
        .device_code => default_device_steps[0..],
        .authorization_code => default_code_steps[0..],
        .api_key, .personal_access_token => default_api_key_steps[0..],
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

    var context = ScriptContext{};

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
        .api_key, .personal_access_token => {},
    }

    return expandScriptSteps(allocator, steps_source, replacements.items, context, &allocations);
}

fn cmdRun(allocator: Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !void {
    if (args.len < 3) {
        try stderr.print("Error: Missing provider name or script input\n\n", .{});
        try stderr.print("USAGE:\n    schlussel run <provider> [options]\n", .{});
        try stderr.print("    schlussel run - [options]\n", .{});
        try stderr.print("    schlussel run --script-json <path|-> [options]\n\n", .{});
        try stderr.print("OPTIONS:\n", .{});
        try stderr.print("    --script-json <path|- >       Resolved script JSON from `schlussel script --resolve`\n", .{});
        try stderr.print("    --method <name>               Authentication method (required if multiple methods)\n", .{});
        try stderr.print("    --redirect-uri <uri>          Redirect URI for auth code (default: http://127.0.0.1:0/callback)\n", .{});
        try stderr.print("    --formula-json <path>         Load a declarative formula JSON\n", .{});
        try stderr.print("    --client-id <id>              OAuth client ID override\n", .{});
        try stderr.print("    --client-secret <secret>      OAuth client secret override\n", .{});
        try stderr.print("    --scope <scopes>              OAuth scopes (space-separated)\n", .{});
        try stderr.print("    --credential <value>          Secret for non-OAuth methods (api_key/personal_access_token)\n", .{});
        try stderr.print("    --identity <value>            Identity label for storage key templates\n", .{});
        try stderr.print("    --open-browser <true|false>   Open the authorization URL (default: true)\n", .{});
        try stderr.print("    --json                        Emit machine-readable JSON output\n", .{});
        try stderr.print("\n", .{});
        return error.MissingArguments;
    }

    var provider_arg: ?[]const u8 = null;
    var start_index: usize = 2;
    var implicit_script_stdin = false;
    if (args.len >= 3) {
        if (std.mem.eql(u8, args[2], "-")) {
            implicit_script_stdin = true;
            start_index = 3;
        } else if (!std.mem.startsWith(u8, args[2], "-")) {
            provider_arg = args[2];
            start_index = 3;
        } else {
            start_index = 2;
        }
    }

    var script_json_path: ?[]const u8 = if (implicit_script_stdin) "-" else null;
    var formula_json_path: ?[]const u8 = null;
    var method_override: ?[]const u8 = null;
    var client_id_override: ?[]const u8 = null;
    var client_secret_override: ?[]const u8 = null;
    var scope_override: ?[]const u8 = null;
    var redirect_uri: []const u8 = "http://127.0.0.1:0/callback";
    var credential_override: ?[]const u8 = null;
    var identity_override: ?[]const u8 = null;
    var open_browser = true;
    var json_output = false;

    var i: usize = start_index;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--json")) {
            json_output = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "-")) {
            if (script_json_path == null) {
                script_json_path = "-";
                continue;
            }
        }
        if (i + 1 >= args.len) {
            try stderr.print("Error: Missing value for option '{s}'\n", .{arg});
            return error.MissingOptionValue;
        }

        if (std.mem.eql(u8, arg, "--script-json")) {
            script_json_path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--formula-json")) {
            formula_json_path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--method")) {
            method_override = args[i + 1];
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
        } else if (std.mem.eql(u8, arg, "--credential")) {
            credential_override = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--identity")) {
            identity_override = args[i + 1];
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

    var script_parsed: ?std.json.Parsed(ScriptOutput) = null;
    defer if (script_parsed) |*parsed| parsed.deinit();
    var resolved_script: ?ResolvedScript = null;
    defer if (resolved_script) |*owned| owned.deinit();

    var script_steps: []const formulas.ScriptStep = &.{};
    var script_context: ?ScriptContext = null;
    var script_method: ?formulas.Method = null;
    if (script_json_path != null) {
        var script_bytes: []const u8 = undefined;
        if (std.mem.eql(u8, script_json_path.?, "-")) {
            const stdin_file = std.fs.File.stdin();
            script_bytes = try stdin_file.readToEndAlloc(allocator, 1024 * 1024);
        } else {
            const script_file = try std.fs.cwd().openFile(script_json_path.?, .{});
            defer script_file.close();
            script_bytes = try script_file.readToEndAlloc(allocator, 1024 * 1024);
        }
        defer allocator.free(script_bytes);

        script_parsed = try std.json.parseFromSlice(ScriptOutput, allocator, script_bytes, .{ .allocate = .alloc_always });
        const parsed = script_parsed.?.value;
        if (parsed.script == null or parsed.script.?.steps == null) {
            try stderr.print("Error: script JSON missing resolved steps\n", .{});
            return error.InvalidParameter;
        };
        if (provider_arg == null) {
            provider_arg = parsed.id;
        }
        if (method_override != null) {
            try stderr.print("Error: --method cannot be used with --script-json\n", .{});
            return error.InvalidParameter;
        }
        script_steps = parsed.script.?.steps.?;
        script_context = parsed.context;
        script_method = parsed.method;
    }

    const provider_name = provider_arg orelse {
        try stderr.print("Error: Missing provider name or script input\n", .{});
        return error.InvalidParameter;
    };

    var thirdPartyFormula: ?formulas.FormulaOwned = null;
    defer if (thirdPartyFormula) |*owner| owner.deinit();

    if (formula_json_path != null) {
        thirdPartyFormula = try formulas.loadFromPath(allocator, formula_json_path.?);
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

    if (script_json_path == null) {
        var method = formula.methods[0];
        if (method_override) |method_name| {
            method = formulas.methodFromString(method_name) orelse {
                try stderr.print("Error: Unknown method '{s}'\n", .{method_name});
                return error.InvalidMethod;
            };
        } else if (formula.methods.len != 1) {
            try stderr.print("Error: --method is required when multiple methods are available\n", .{});
            return error.MissingArguments;
        }

        resolved_script = try resolveScriptSteps(
            allocator,
            formula,
            method,
            client_id_override,
            client_secret_override,
            scope_override,
            redirect_uri,
        );
        script_steps = resolved_script.?.steps;
        script_context = resolved_script.?.context;
        script_method = method;
    }

    const method = script_method orelse {
        try stderr.print("Error: script JSON missing method\n", .{});
        return error.InvalidParameter;
    };
    const context = script_context orelse switch (method) {
        .device_code, .authorization_code => {
            try stderr.print("Error: script JSON missing context\n", .{});
            return error.InvalidParameter;
        },
        .api_key, .personal_access_token => ScriptContext{},
    };

    const storage_key = try storageKeyFromFormula(allocator, formula, method, identity_override);
    defer allocator.free(storage_key);

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

    const info_out = if (json_output) stderr else stdout;
    var token: session.Token = undefined;

    if (script_steps.len > 0) {
        try info_out.print("\nScript steps:\n", .{});
        for (script_steps, 0..) |step, idx| {
            if (step.note) |note| {
                try info_out.print("  {d}. {s} ({s})\n", .{ idx + 1, step.@"type", note });
            } else {
                try info_out.print("  {d}. {s}\n", .{ idx + 1, step.@"type" });
            }
        }
    }

    switch (method) {
        .device_code => {
            const device_code = context.device_code orelse {
                try stderr.print("Error: script context missing device_code\n", .{});
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
                try info_out.print("\nOpening browser for authorization...\n", .{});
                try info_out.print("If the browser doesn't open, visit:\n{s}\n\n", .{authorize_url});
                callback.openBrowser(authorize_url) catch {};
            } else {
                try info_out.print("\nVisit the following URL to authorize:\n{s}\n\n", .{authorize_url});
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
        .api_key, .personal_access_token => {
            var secret_owned: ?[]const u8 = null;
            defer if (secret_owned) |value| allocator.free(value);
            const secret = credential_override orelse blk: {
                try info_out.print("\nEnter {s}: ", .{switch (method) {
                    .api_key => "API key",
                    .personal_access_token => "personal access token",
                    else => "credential",
                }});
                const stdin_reader = std.fs.File.stdin().reader();
                const line = (try stdin_reader.readUntilDelimiterOrEofAlloc(allocator, '\n', 1024 * 1024)) orelse {
                    return error.EndOfStream;
                };
                defer allocator.free(line);
                const trimmed = std.mem.trimRight(u8, line, "\r\n");
                if (trimmed.len == 0) {
                    try stderr.print("Error: credential cannot be empty\n", .{});
                    return error.InvalidParameter;
                }
                secret_owned = try allocator.dupe(u8, trimmed);
                break :blk secret_owned.?;
            };

            token = try tokenFromCredential(allocator, method, secret);
        },
    }
    defer token.deinit();

    try client.saveToken(storage_key, token);
    if (json_output) {
        const result = RunResult{
            .storage_key = storage_key,
            .method = method,
            .token = tokenToOutput(token),
        };
        var out = std.Io.Writer.Allocating.init(allocator);
        defer out.deinit();
        try std.json.Stringify.value(result, .{ .whitespace = .indent_2 }, &out.writer);
        try stdout.print("{s}\n", .{out.written()});
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

fn tokenFromCredential(
    allocator: Allocator,
    method: formulas.Method,
    credential: []const u8,
) !session.Token {
    if (credential.len == 0) {
        return error.InvalidParameter;
    }

    const token_type = switch (method) {
        .api_key => "api_key",
        .personal_access_token => "personal_access_token",
        else => return error.UnsupportedOperation,
    };

    return session.Token.init(allocator, credential, token_type);
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

fn storageKeyFromFormula(
    allocator: Allocator,
    formula: *const formulas.Formula,
    method: formulas.Method,
    identity: ?[]const u8,
) ![]const u8 {
    const default_template = "{formula_id}:{method}";
    const template = if (formula.storage) |storage| storage.key_template orelse default_template else default_template;
    if (identity == null and std.mem.indexOf(u8, template, "{identity}") != null) {
        return error.InvalidParameter;
    }

    var replacements = std.ArrayListUnmanaged(Replacement){};
    defer replacements.deinit(allocator);
    try replacements.append(allocator, .{ .key = "formula_id", .value = formula.id });
    try replacements.append(allocator, .{ .key = "method", .value = @tagName(method) });
    if (identity) |value| {
        try replacements.append(allocator, .{ .key = "identity", .value = value });
    }

    return expandTemplate(allocator, template, replacements.items);
}

const Command = enum {
    script,
    run,
    token,
    register,
    register_read,
    register_update,
    register_delete,
    help,

    pub fn fromString(str: []const u8) ?Command {
        const eql = std.mem.eql;
        if (eql(u8, str, "script")) return .script;
        if (eql(u8, str, "run")) return .run;
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
        .script => try cmdScript(allocator, args, stdout, stderr),
        .run => try cmdRun(allocator, args, stdout, stderr),
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
        \\    script              Emit a script for a provider
        \\    run                 Execute a resolved script or resolve+run
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
        \\    # Emit a JSON script
        \\    schlussel script github
        \\
        \\    # Emit a JSON script from a custom formula
        \\    schlussel script acme --formula-json ~/formulas/acme.json
        \\
        \\    # Print the formula schema
        \\    schlussel script --json-schema
        \\
        \\    # Execute a resolved script
        \\    schlussel run github --script-json script.json
        \\
        \\    # Resolve and run in one command
        \\    schlussel run github --method device_code
        \\
        \\    # Execute a resolved script from stdin
        \\    schlussel run --script-json -
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

test "tokenFromCredential sets token type for non-oauth methods" {
    const allocator = std.testing.allocator;

    var api_token = try tokenFromCredential(allocator, .api_key, "api-secret");
    defer api_token.deinit();
    try std.testing.expectEqualStrings("api_key", api_token.token_type);
    try std.testing.expectEqualStrings("api-secret", api_token.access_token);

    var pat_token = try tokenFromCredential(allocator, .personal_access_token, "pat-secret");
    defer pat_token.deinit();
    try std.testing.expectEqualStrings("personal_access_token", pat_token.token_type);
    try std.testing.expectEqualStrings("pat-secret", pat_token.access_token);
}

test "storageKeyFromFormula expands default template" {
    const allocator = std.testing.allocator;

    const formula = formulas.Formula{
        .schema = "v1",
        .id = "acme",
        .label = "Acme API",
        .methods = &.{.api_key},
        .authorization_endpoint = null,
        .token_endpoint = null,
        .device_authorization_endpoint = null,
        .scope = null,
        .storage = null,
        .public_clients = null,
        .script = null,
        .quirks = null,
    };

    const key = try storageKeyFromFormula(allocator, &formula, .api_key, null);
    defer allocator.free(key);
    try std.testing.expectEqualStrings("acme:api_key", key);
}

test "storageKeyFromFormula uses identity placeholder when provided" {
    const allocator = std.testing.allocator;

    const formula = formulas.Formula{
        .schema = "v1",
        .id = "acme",
        .label = "Acme API",
        .methods = &.{.api_key},
        .authorization_endpoint = null,
        .token_endpoint = null,
        .device_authorization_endpoint = null,
        .scope = null,
        .storage = .{
            .key_template = "{formula_id}:{method}:{identity}",
            .label = null,
            .value_label = null,
            .identity_label = null,
            .identity_hint = null,
            .rotation_url = null,
            .rotation_hint = null,
        },
        .public_clients = null,
        .script = null,
        .quirks = null,
    };

    const key = try storageKeyFromFormula(allocator, &formula, .api_key, "alice");
    defer allocator.free(key);
    try std.testing.expectEqualStrings("acme:api_key:alice", key);
}

test "storageKeyFromFormula requires identity when template references it" {
    const allocator = std.testing.allocator;

    const formula = formulas.Formula{
        .schema = "v1",
        .id = "acme",
        .label = "Acme API",
        .methods = &.{.api_key},
        .authorization_endpoint = null,
        .token_endpoint = null,
        .device_authorization_endpoint = null,
        .scope = null,
        .storage = .{
            .key_template = "{formula_id}:{method}:{identity}",
            .label = null,
            .value_label = null,
            .identity_label = null,
            .identity_hint = null,
            .rotation_url = null,
            .rotation_hint = null,
        },
        .public_clients = null,
        .script = null,
        .quirks = null,
    };

    const result = storageKeyFromFormula(allocator, &formula, .api_key, null);
    try std.testing.expectError(error.InvalidParameter, result);
}

fn cmdScript(allocator: Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !void {
    if (args.len >= 3 and std.mem.eql(u8, args[2], "--json-schema")) {
        try stdout.print("{s}\n", .{formula_schema_v1});
        return;
    }

    if (args.len < 3) {
        try stderr.print("Error: Missing provider name\n\n", .{});
        try stderr.print("USAGE:\n    schlussel script <provider> [options]\n\n", .{});
        try stderr.print("OPTIONS:\n", .{});
        try stderr.print("    --json-schema                 Print the formula JSON schema\n", .{});
        try stderr.print("    --formula-json <path>         Load a declarative formula JSON\n", .{});
        try stderr.print("    --method <name>               Filter to a single method\n", .{});
        try stderr.print("    --client-id <id>              OAuth client ID override\n", .{});
        try stderr.print("    --client-secret <secret>      OAuth client secret override\n", .{});
        try stderr.print("    --scope <scopes>              OAuth scopes (space-separated)\n", .{});
        try stderr.print("    --redirect-uri <uri>          Redirect URI (default: http://127.0.0.1:0/callback)\n", .{});
        try stderr.print("    --resolve                      Resolve placeholders into a script context\n", .{});
        return error.MissingArguments;
    }

    const provider_arg = args[2];
    var formula_json_path: ?[]const u8 = null;
    var method_filter: ?[]const u8 = null;
    var client_id_override: ?[]const u8 = null;
    var client_secret_override: ?[]const u8 = null;
    var scope_override: ?[]const u8 = null;
    var redirect_uri: []const u8 = "http://127.0.0.1:0/callback";
    var resolve_script = false;

    var i: usize = 3;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (i + 1 >= args.len) {
            try stderr.print("Error: Missing value for option '{s}'\n", .{arg});
            return error.MissingOptionValue;
        }

        if (std.mem.eql(u8, arg, "--json-schema")) {
            try stdout.print("{s}\n", .{formula_schema_v1});
            return;
        } else if (std.mem.eql(u8, arg, "--formula-json")) {
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
            resolve_script = true;
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

    var resolved_steps: ?ResolvedScript = null;
    defer if (resolved_steps) |*owned| owned.deinit();

    var script_context: ?ScriptContext = null;
    var script_method: ?formulas.Method = null;
    var script_out: ?formulas.Script = null;
    if (resolve_script) {
        const method = selected_method orelse {
            try stderr.print("Error: --method is required to resolve a script\n", .{});
            return error.MissingArguments;
        };

        resolved_steps = try resolveScriptSteps(
            allocator,
            formula,
            method,
            client_id_override,
            client_secret_override,
            scope_override,
            redirect_uri,
        );
        script_context = resolved_steps.?.context;
        script_method = method;
        const register = if (formula.script) |script| script.register else null;
        script_out = formulas.Script{
            .register = register,
            .steps = resolved_steps.?.steps,
        };
    } else {
        script_out = formula.script;
    }

    const output = ScriptOutput{
        .id = formula.id,
        .label = formula.label,
        .methods = methods,
        .script = script_out,
        .storage = formula.storage,
        .method = script_method,
        .context = script_context,
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
