const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;

pub const Error = error{
    InvalidRootDocument,
    MissingField,
    InvalidField,
    InvalidFlow,
};

pub const Flow = enum {
    authorization_code,
    device_code,
};

pub fn flowFromString(value: []const u8) ?Flow {
    if (std.mem.eql(u8, value, "authorization_code")) return .authorization_code;
    if (std.mem.eql(u8, value, "device_code")) return .device_code;
    return null;
}

pub const Onboarding = struct {
    register_url: []const u8,
    steps: []const []const u8,
};

pub const PublicClient = struct {
    name: []const u8,
    id: []const u8,
    secret: ?[]const u8,
    source: ?[]const u8,
    flows: ?[]const Flow,
};

pub const Quirks = struct {
    dynamic_registration_endpoint: ?[]const u8,
    token_response: ?[]const u8,
    extra_response_fields: ?[]const []const u8,
    /// Custom device code polling endpoint pattern (e.g., "/api/auth/device_code/{device_code}")
    /// If set, uses GET polling instead of standard RFC 8628 token endpoint POST
    device_code_poll_endpoint: ?[]const u8,
    /// Custom browser URL pattern for device code flow (e.g., "/auth/device_codes/{device_code}?type=cli")
    /// The {device_code} placeholder will be replaced with the actual code
    device_code_browser_url: ?[]const u8,
};

pub const Formula = struct {
    id: []const u8,
    label: []const u8,
    flows: []const Flow,
    authorization_endpoint: []const u8,
    token_endpoint: []const u8,
    device_authorization_endpoint: ?[]const u8,
    scope: ?[]const u8,
    public_clients: ?[]const PublicClient,
    onboarding: ?Onboarding,
    quirks: ?Quirks,

    /// Get the default public client (first one in the list)
    pub fn getDefaultClient(self: *const Formula) ?*const PublicClient {
        if (self.public_clients) |clients| {
            if (clients.len > 0) {
                return &clients[0];
            }
        }
        return null;
    }

    /// Find a public client by name
    pub fn getClientByName(self: *const Formula, name: []const u8) ?*const PublicClient {
        if (self.public_clients) |clients| {
            for (clients) |*client| {
                if (std.mem.eql(u8, client.name, name)) {
                    return client;
                }
            }
        }
        return null;
    }
};

// Embedded formula JSON files
const github_json = @embedFile("formulas/github.json");
const codex_json = @embedFile("formulas/codex.json");
const claude_json = @embedFile("formulas/claude.json");

// Builtin formulas loaded at first access
var builtin_formulas_loaded = false;
var builtin_formulas: [3]FormulaOwned = undefined;

pub fn findById(allocator: Allocator, id: []const u8) !?*const Formula {
    if (!builtin_formulas_loaded) {
        try loadBuiltinFormulas(allocator);
        builtin_formulas_loaded = true;
    }

    for (&builtin_formulas) |*formula| {
        if (std.mem.eql(u8, formula.formula.id, id)) return formula.asConst();
    }
    return null;
}

fn loadBuiltinFormulas(allocator: Allocator) !void {
    builtin_formulas[0] = try loadFromJsonSlice(allocator, github_json);
    builtin_formulas[1] = try loadFromJsonSlice(allocator, codex_json);
    builtin_formulas[2] = try loadFromJsonSlice(allocator, claude_json);
}

pub fn deinitBuiltinFormulas() void {
    if (!builtin_formulas_loaded) return;
    for (&builtin_formulas) |*formula| {
        formula.deinit();
    }
    builtin_formulas_loaded = false;
}

pub const FormulaOwned = struct {
    allocator: Allocator,
    formula: Formula,
    flows_alloc: ?[]const Flow,
    steps_alloc: ?[]const []const u8,
    extra_fields_alloc: ?[]const []const u8,
    public_clients_alloc: ?[]const PublicClient,
    parsed: json.Parsed(json.Value),

    pub fn deinit(self: *FormulaOwned) void {
        if (self.flows_alloc) |arr| self.allocator.free(arr);
        if (self.steps_alloc) |arr| self.allocator.free(arr);
        if (self.extra_fields_alloc) |arr| self.allocator.free(arr);
        if (self.public_clients_alloc) |arr| {
            for (arr) |client| {
                if (client.flows) |flows| self.allocator.free(flows);
            }
            self.allocator.free(arr);
        }
        self.parsed.deinit();
    }

    pub fn asConst(self: *const FormulaOwned) *const Formula {
        return &self.formula;
    }
};

fn expectString(value: json.Value) ![]const u8 {
    return switch (value) {
        .string => |s| s,
        .number_string => |s| s,
        else => return Error.InvalidField,
    };
}

fn parseStringArray(allocator: Allocator, value: json.Value) ![]const []const u8 {
    const arr = switch (value) {
        .array => |a| a,
        else => return Error.InvalidField,
    };

    var slice = try allocator.alloc([]const u8, arr.items.len);
    errdefer allocator.free(slice);
    for (arr.items, 0..) |item, idx| {
        slice[idx] = try expectString(item);
    }
    return slice;
}

fn optionalString(value: ?json.Value) !?[]const u8 {
    if (value) |v| {
        if (v == .null) return null;
        return try expectString(v);
    }
    return null;
}

fn optionalStringArray(allocator: Allocator, value: ?json.Value) !?[]const []const u8 {
    if (value) |v| {
        if (v == .null) return null;
        return try parseStringArray(allocator, v);
    }
    return null;
}

fn parseFlows(allocator: Allocator, value: json.Value) ![]const Flow {
    const arr = switch (value) {
        .array => |a| a,
        else => return Error.InvalidField,
    };

    var slice = try allocator.alloc(Flow, arr.items.len);
    errdefer allocator.free(slice);
    for (arr.items, 0..) |item, idx| {
        const text = try expectString(item);
        slice[idx] = flowFromString(text) orelse return Error.InvalidFlow;
    }
    return slice;
}

fn parsePublicClients(allocator: Allocator, value: json.Value) ![]const PublicClient {
    const arr = switch (value) {
        .array => |a| a,
        else => return Error.InvalidField,
    };

    var slice = try allocator.alloc(PublicClient, arr.items.len);
    errdefer allocator.free(slice);
    var parsed_count: usize = 0;
    errdefer {
        for (slice[0..parsed_count]) |client| {
            if (client.flows) |flows| allocator.free(flows);
        }
    }
    for (arr.items, 0..) |item, idx| {
        const obj = switch (item) {
            .object => |o| o,
            else => return Error.InvalidField,
        };

        var flows: ?[]const Flow = null;
        if (obj.get("flows")) |flows_value| {
            if (flows_value != .null) {
                flows = try parseFlows(allocator, flows_value);
            }
        }
        errdefer if (flows) |arr| allocator.free(arr);

        slice[idx] = PublicClient{
            .name = try expectString(obj.get("name") orelse return Error.MissingField),
            .id = try expectString(obj.get("id") orelse return Error.MissingField),
            .secret = try optionalString(obj.get("secret")),
            .source = try optionalString(obj.get("source")),
            .flows = flows,
        };
        flows = null;
        parsed_count += 1;
    }
    return slice;
}

pub fn loadFromJsonSlice(allocator: Allocator, slice: []const u8) !FormulaOwned {
    var parsed = try json.parseFromSlice(json.Value, allocator, slice, .{ .allocate = .alloc_always });
    errdefer parsed.deinit();

    const root = switch (parsed.value) {
        .object => |obj| obj,
        else => return Error.InvalidRootDocument,
    };

    const id = try expectString(root.get("id") orelse return Error.MissingField);
    const label = try expectString(root.get("label") orelse return Error.MissingField);

    const endpoints_value = root.get("endpoints") orelse return Error.MissingField;
    const endpoint_obj = switch (endpoints_value) {
        .object => |o| o,
        else => return Error.InvalidField,
    };

    const authorization_endpoint = try expectString(endpoint_obj.get("authorize") orelse return Error.MissingField);
    const token_endpoint = try expectString(endpoint_obj.get("token") orelse return Error.MissingField);
    const device_authorization_endpoint = try optionalString(endpoint_obj.get("device"));

    const flows_value = root.get("flows") orelse return Error.MissingField;
    const flows = try parseFlows(allocator, flows_value);
    errdefer allocator.free(flows);

    var onboarding: ?Onboarding = null;
    var steps: ?[]const []const u8 = null;
    if (root.get("onboarding")) |onboarding_value| {
        const onboarding_obj = switch (onboarding_value) {
            .object => |o| o,
            else => return Error.InvalidField,
        };

        const register_url = try expectString(onboarding_obj.get("register_url") orelse return Error.MissingField);
        steps = try parseStringArray(allocator, onboarding_obj.get("steps") orelse return Error.MissingField);

        onboarding = Onboarding{
            .register_url = register_url,
            .steps = steps.?,
        };
    }
    errdefer if (steps) |s| allocator.free(s);

    const scope = try optionalString(root.get("scope"));

    var public_clients: ?[]const PublicClient = null;
    if (root.get("public_clients")) |clients_value| {
        public_clients = try parsePublicClients(allocator, clients_value);
    }
    errdefer if (public_clients) |pc| allocator.free(pc);

    var quirks: ?Quirks = null;
    if (root.get("quirks")) |quirks_value| {
        const quirks_obj = switch (quirks_value) {
            .object => |o| o,
            else => return Error.InvalidField,
        };

        const dynamic_endpoint = try optionalString(quirks_obj.get("dynamic_registration_endpoint"));
        const token_response = try optionalString(quirks_obj.get("token_response"));
        const extra_fields = try optionalStringArray(allocator, quirks_obj.get("extra_response_fields"));
        errdefer if (extra_fields) |ef| allocator.free(ef);
        const device_code_poll_endpoint = try optionalString(quirks_obj.get("device_code_poll_endpoint"));
        const device_code_browser_url = try optionalString(quirks_obj.get("device_code_browser_url"));

        quirks = Quirks{
            .dynamic_registration_endpoint = dynamic_endpoint,
            .token_response = token_response,
            .extra_response_fields = extra_fields,
            .device_code_poll_endpoint = device_code_poll_endpoint,
            .device_code_browser_url = device_code_browser_url,
        };
    }
    // Note: extra_fields errdefer is handled inside the if block above

    return FormulaOwned{
        .allocator = allocator,
        .formula = Formula{
            .id = id,
            .label = label,
            .flows = flows,
            .authorization_endpoint = authorization_endpoint,
            .token_endpoint = token_endpoint,
            .device_authorization_endpoint = device_authorization_endpoint,
            .scope = scope,
            .public_clients = public_clients,
            .onboarding = onboarding,
            .quirks = quirks,
        },
        .flows_alloc = flows,
        .steps_alloc = steps,
        .extra_fields_alloc = if (quirks) |q| q.extra_response_fields else null,
        .public_clients_alloc = public_clients,
        .parsed = parsed,
    };
}

pub fn loadFromPath(allocator: Allocator, path: []const u8) !FormulaOwned {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const buffer = try file.readToEndAlloc(allocator, 4096);
    defer allocator.free(buffer);

    return loadFromJsonSlice(allocator, buffer);
}

// ============================================================================
// Tests
// ============================================================================

test "FormulaOwned: parse minimal formula without leaks" {
    const allocator = std.testing.allocator;

    const minimal_json =
        \\{
        \\  "id": "test",
        \\  "label": "Test Provider",
        \\  "flows": ["device_code"],
        \\  "endpoints": {
        \\    "authorize": "https://example.com/authorize",
        \\    "token": "https://example.com/token"
        \\  }
        \\}
    ;

    var owned = try loadFromJsonSlice(allocator, minimal_json);
    defer owned.deinit();

    try std.testing.expectEqualStrings("test", owned.formula.id);
    try std.testing.expectEqualStrings("Test Provider", owned.formula.label);
    try std.testing.expectEqual(@as(usize, 1), owned.formula.flows.len);
    try std.testing.expectEqual(Flow.device_code, owned.formula.flows[0]);
}

test "FormulaOwned: parse formula with public_clients without leaks" {
    const allocator = std.testing.allocator;

    const json_with_clients =
        \\{
        \\  "id": "github",
        \\  "label": "GitHub",
        \\  "flows": ["device_code", "authorization_code"],
        \\  "endpoints": {
        \\    "authorize": "https://github.com/login/oauth/authorize",
        \\    "token": "https://github.com/login/oauth/access_token",
        \\    "device": "https://github.com/login/device/code"
        \\  },
        \\  "scope": "repo read:org",
        \\  "public_clients": [
        \\    {
        \\      "name": "gh-cli",
        \\      "id": "abc123",
        \\      "secret": "secret456",
        \\      "source": "https://github.com/cli/cli",
        \\      "flows": ["device_code"]
        \\    },
        \\    {
        \\      "name": "another-cli",
        \\      "id": "def789",
        \\      "flows": ["authorization_code"]
        \\    }
        \\  ]
        \\}
    ;

    var owned = try loadFromJsonSlice(allocator, json_with_clients);
    defer owned.deinit();

    try std.testing.expectEqualStrings("github", owned.formula.id);
    try std.testing.expectEqual(@as(usize, 2), owned.formula.flows.len);
    try std.testing.expect(owned.formula.public_clients != null);
    try std.testing.expectEqual(@as(usize, 2), owned.formula.public_clients.?.len);

    // Test getDefaultClient
    const default_client = owned.formula.getDefaultClient();
    try std.testing.expect(default_client != null);
    try std.testing.expectEqualStrings("gh-cli", default_client.?.name);
    try std.testing.expectEqualStrings("abc123", default_client.?.id);
    try std.testing.expectEqualStrings("secret456", default_client.?.secret.?);
    try std.testing.expect(default_client.?.flows != null);
    try std.testing.expectEqual(@as(usize, 1), default_client.?.flows.?.len);
    try std.testing.expectEqual(Flow.device_code, default_client.?.flows.?[0]);

    // Test getClientByName
    const found = owned.formula.getClientByName("another-cli");
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings("def789", found.?.id);
    try std.testing.expect(found.?.secret == null);
    try std.testing.expect(found.?.flows != null);
    try std.testing.expectEqual(@as(usize, 1), found.?.flows.?.len);
    try std.testing.expectEqual(Flow.authorization_code, found.?.flows.?[0]);

    // Test not found
    const not_found = owned.formula.getClientByName("nonexistent");
    try std.testing.expect(not_found == null);
}

test "FormulaOwned: parse formula with onboarding without leaks" {
    const allocator = std.testing.allocator;

    const json_with_onboarding =
        \\{
        \\  "id": "custom",
        \\  "label": "Custom Provider",
        \\  "flows": ["authorization_code"],
        \\  "endpoints": {
        \\    "authorize": "https://custom.com/authorize",
        \\    "token": "https://custom.com/token"
        \\  },
        \\  "onboarding": {
        \\    "register_url": "https://custom.com/register",
        \\    "steps": [
        \\      "Go to the registration page",
        \\      "Create a new OAuth application",
        \\      "Copy the client ID"
        \\    ]
        \\  }
        \\}
    ;

    var owned = try loadFromJsonSlice(allocator, json_with_onboarding);
    defer owned.deinit();

    try std.testing.expect(owned.formula.onboarding != null);
    try std.testing.expectEqualStrings("https://custom.com/register", owned.formula.onboarding.?.register_url);
    try std.testing.expectEqual(@as(usize, 3), owned.formula.onboarding.?.steps.len);
}

test "FormulaOwned: parse formula with quirks without leaks" {
    const allocator = std.testing.allocator;

    const json_with_quirks =
        \\{
        \\  "id": "quirky",
        \\  "label": "Quirky Provider",
        \\  "flows": ["device_code"],
        \\  "endpoints": {
        \\    "authorize": "https://quirky.com/authorize",
        \\    "token": "https://quirky.com/token"
        \\  },
        \\  "quirks": {
        \\    "dynamic_registration_endpoint": "https://quirky.com/register",
        \\    "token_response": "custom",
        \\    "extra_response_fields": ["custom_field", "another_field"],
        \\    "device_code_poll_endpoint": "/api/poll/{device_code}",
        \\    "device_code_browser_url": "/auth/{device_code}"
        \\  }
        \\}
    ;

    var owned = try loadFromJsonSlice(allocator, json_with_quirks);
    defer owned.deinit();

    try std.testing.expect(owned.formula.quirks != null);
    const quirks = owned.formula.quirks.?;
    try std.testing.expectEqualStrings("https://quirky.com/register", quirks.dynamic_registration_endpoint.?);
    try std.testing.expectEqualStrings("custom", quirks.token_response.?);
    try std.testing.expectEqual(@as(usize, 2), quirks.extra_response_fields.?.len);
    try std.testing.expectEqualStrings("/api/poll/{device_code}", quirks.device_code_poll_endpoint.?);
}

test "FormulaOwned: parse full formula with all fields without leaks" {
    const allocator = std.testing.allocator;

    const full_json =
        \\{
        \\  "id": "full",
        \\  "label": "Full Provider",
        \\  "flows": ["device_code", "authorization_code"],
        \\  "endpoints": {
        \\    "authorize": "https://full.com/authorize",
        \\    "token": "https://full.com/token",
        \\    "device": "https://full.com/device"
        \\  },
        \\  "scope": "read write admin",
        \\  "public_clients": [
        \\    {"name": "cli", "id": "id1", "secret": "secret1", "source": "https://source.com"}
        \\  ],
        \\  "onboarding": {
        \\    "register_url": "https://full.com/register",
        \\    "steps": ["Step 1", "Step 2"]
        \\  },
        \\  "quirks": {
        \\    "dynamic_registration_endpoint": "https://full.com/dyn",
        \\    "extra_response_fields": ["field1"]
        \\  }
        \\}
    ;

    var owned = try loadFromJsonSlice(allocator, full_json);
    defer owned.deinit();

    try std.testing.expectEqualStrings("full", owned.formula.id);
    try std.testing.expectEqualStrings("read write admin", owned.formula.scope.?);
    try std.testing.expect(owned.formula.public_clients != null);
    try std.testing.expect(owned.formula.onboarding != null);
    try std.testing.expect(owned.formula.quirks != null);
    try std.testing.expectEqualStrings("https://full.com/device", owned.formula.device_authorization_endpoint.?);
}

test "FormulaOwned: error handling does not leak on invalid JSON" {
    const allocator = std.testing.allocator;

    // Invalid JSON syntax
    const result1 = loadFromJsonSlice(allocator, "{ invalid json }");
    try std.testing.expectError(error.SyntaxError, result1);

    // Missing required field
    const missing_id =
        \\{
        \\  "label": "Test",
        \\  "flows": ["device_code"],
        \\  "endpoints": {"authorize": "https://x.com/a", "token": "https://x.com/t"}
        \\}
    ;
    const result2 = loadFromJsonSlice(allocator, missing_id);
    try std.testing.expectError(Error.MissingField, result2);

    // Invalid flow type
    const invalid_flow =
        \\{
        \\  "id": "test",
        \\  "label": "Test",
        \\  "flows": ["invalid_flow"],
        \\  "endpoints": {"authorize": "https://x.com/a", "token": "https://x.com/t"}
        \\}
    ;
    const result3 = loadFromJsonSlice(allocator, invalid_flow);
    try std.testing.expectError(Error.InvalidFlow, result3);

    // Not an object
    const result4 = loadFromJsonSlice(allocator, "[]");
    try std.testing.expectError(Error.InvalidRootDocument, result4);
}

test "builtin formulas: findById and cleanup without leaks" {
    const allocator = std.testing.allocator;

    // Ensure clean state
    deinitBuiltinFormulas();

    // First lookup loads formulas
    const github = try findById(allocator, "github");
    try std.testing.expect(github != null);
    try std.testing.expectEqualStrings("github", github.?.id);

    // Second lookup returns cached formula
    const github2 = try findById(allocator, "github");
    try std.testing.expect(github2 != null);
    try std.testing.expect(github == github2); // Same pointer

    // Non-existent formula
    const nonexistent = try findById(allocator, "nonexistent");
    try std.testing.expect(nonexistent == null);

    // Clean up
    deinitBuiltinFormulas();
}

test "builtin formulas: codex and claude formulas load correctly" {
    const allocator = std.testing.allocator;

    // Ensure clean state
    deinitBuiltinFormulas();

    // Test Codex formula
    const codex = try findById(allocator, "codex");
    try std.testing.expect(codex != null);
    try std.testing.expectEqualStrings("codex", codex.?.id);
    try std.testing.expectEqualStrings("OpenAI Codex", codex.?.label);
    try std.testing.expectEqualStrings("https://auth.openai.com/oauth/authorize", codex.?.authorization_endpoint);
    try std.testing.expectEqualStrings("https://auth.openai.com/oauth/token", codex.?.token_endpoint);
    try std.testing.expect(codex.?.public_clients != null);
    try std.testing.expect(codex.?.public_clients.?.len == 1);
    try std.testing.expectEqualStrings("codex-cli", codex.?.public_clients.?[0].name);
    try std.testing.expectEqualStrings("app_EMoamEEZ73f0CkXaXp7hrann", codex.?.public_clients.?[0].id);

    // Test Claude formula
    const claude = try findById(allocator, "claude");
    try std.testing.expect(claude != null);
    try std.testing.expectEqualStrings("claude", claude.?.id);
    try std.testing.expectEqualStrings("Claude Code (Anthropic)", claude.?.label);
    try std.testing.expectEqualStrings("https://console.anthropic.com/oauth/authorize", claude.?.authorization_endpoint);
    try std.testing.expectEqualStrings("https://console.anthropic.com/v1/oauth/token", claude.?.token_endpoint);
    try std.testing.expect(claude.?.public_clients != null);
    try std.testing.expect(claude.?.public_clients.?.len == 1);
    try std.testing.expectEqualStrings("claude-code", claude.?.public_clients.?[0].name);
    try std.testing.expectEqualStrings("9d1c250a-e61b-44d9-88ed-5944d1962f5e", claude.?.public_clients.?[0].id);

    // Clean up
    deinitBuiltinFormulas();
}

test "flowFromString: returns correct flows" {
    try std.testing.expectEqual(Flow.authorization_code, flowFromString("authorization_code").?);
    try std.testing.expectEqual(Flow.device_code, flowFromString("device_code").?);
    try std.testing.expect(flowFromString("invalid") == null);
    try std.testing.expect(flowFromString("") == null);
}
