const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;

pub const Error = error{
    InvalidRootDocument,
    MissingField,
    InvalidField,
    InvalidMethod,
    InvalidSchema,
    MissingEndpoint,
    MethodNotFound,
    ApiNotFound,
};

// ============================================================================
// Script Types
// ============================================================================

pub const ScriptRegister = struct {
    url: []const u8,
    steps: []const []const u8,
};

pub const ScriptStep = struct {
    @"type": []const u8,
    value: ?[]const u8,
    note: ?[]const u8,
};

// ============================================================================
// Method Definition (v2 schema)
// ============================================================================

pub const Endpoints = struct {
    authorize: ?[]const u8 = null,
    token: ?[]const u8 = null,
    device: ?[]const u8 = null,
    registration: ?[]const u8 = null,
};

pub const DynamicRegistration = struct {
    client_name: ?[]const u8 = null,
    grant_types: ?[]const []const u8 = null,
    response_types: ?[]const []const u8 = null,
    token_endpoint_auth_method: ?[]const u8 = null,
};

pub const MethodDef = struct {
    name: []const u8,
    label: ?[]const u8 = null,
    endpoints: ?Endpoints = null,
    scope: ?[]const u8 = null,
    register: ?ScriptRegister = null,
    script: ?[]const ScriptStep = null,
    dynamic_registration: ?DynamicRegistration = null,

    /// Check if this method is an OAuth authorization code flow
    pub fn isAuthorizationCode(self: *const MethodDef) bool {
        if (self.endpoints) |ep| {
            return ep.authorize != null and ep.token != null and ep.device == null;
        }
        return false;
    }

    /// Check if this method is an OAuth device code flow
    pub fn isDeviceCode(self: *const MethodDef) bool {
        if (self.endpoints) |ep| {
            return ep.device != null and ep.token != null;
        }
        return false;
    }

    /// Check if this method is an API key / manual credential flow
    pub fn isApiKey(self: *const MethodDef) bool {
        // No OAuth endpoints means it's a manual credential entry
        if (self.endpoints) |ep| {
            return ep.authorize == null and ep.token == null and ep.device == null;
        }
        return true;
    }

    /// Check if this method uses dynamic client registration
    pub fn usesDynamicRegistration(self: *const MethodDef) bool {
        return self.dynamic_registration != null;
    }
};

// ============================================================================
// API Definition (v2 schema)
// ============================================================================

pub const ApiDef = struct {
    name: []const u8,
    base_url: []const u8,
    auth_header: []const u8,
    docs_url: ?[]const u8 = null,
    spec_url: ?[]const u8 = null,
    spec_type: ?[]const u8 = null,
    methods: []const []const u8, // References to method names
};

// ============================================================================
// Client Definition (v2 schema)
// ============================================================================

pub const Client = struct {
    name: []const u8,
    id: []const u8,
    secret: ?[]const u8 = null,
    source: ?[]const u8 = null,
    methods: ?[]const []const u8 = null, // Which methods this client supports
    redirect_uri: ?[]const u8 = null, // Pre-registered redirect URI for this client
};

// ============================================================================
// Identity Hints (v2 schema)
// ============================================================================

pub const Identity = struct {
    label: ?[]const u8 = null,
    hint: ?[]const u8 = null,
};

// ============================================================================
// Formula (v2 schema)
// ============================================================================

pub const Formula = struct {
    schema: []const u8,
    id: []const u8,
    label: []const u8,
    methods: []const MethodDef,
    apis: []const ApiDef,
    clients: ?[]const Client = null,
    identity: ?Identity = null,

    /// Get a method by name
    pub fn getMethod(self: *const Formula, name: []const u8) ?*const MethodDef {
        for (self.methods) |*method| {
            if (std.mem.eql(u8, method.name, name)) {
                return method;
            }
        }
        return null;
    }

    /// Get an API by name
    pub fn getApi(self: *const Formula, name: []const u8) ?*const ApiDef {
        for (self.apis) |*api| {
            if (std.mem.eql(u8, api.name, name)) {
                return api;
            }
        }
        return null;
    }

    /// Get the default client (first one in the list)
    pub fn getDefaultClient(self: *const Formula) ?*const Client {
        if (self.clients) |clients| {
            if (clients.len > 0) {
                return &clients[0];
            }
        }
        return null;
    }

    /// Get the default client for a specific method
    pub fn getDefaultClientForMethod(self: *const Formula, method_name: []const u8) ?*const Client {
        if (self.clients) |clients| {
            for (clients) |*client| {
                if (client.methods) |supported_methods| {
                    for (supported_methods) |m| {
                        if (std.mem.eql(u8, m, method_name)) {
                            return client;
                        }
                    }
                } else {
                    // No method restriction, this client works for all methods
                    return client;
                }
            }
        }
        return null;
    }

    /// Find a client by name
    pub fn getClientByName(self: *const Formula, name: []const u8) ?*const Client {
        if (self.clients) |clients| {
            for (clients) |*client| {
                if (std.mem.eql(u8, client.name, name)) {
                    return client;
                }
            }
        }
        return null;
    }

    /// Get the first method (for formulas with a single method)
    pub fn getFirstMethod(self: *const Formula) ?*const MethodDef {
        if (self.methods.len > 0) {
            return &self.methods[0];
        }
        return null;
    }

    /// List method names
    pub fn listMethodNames(self: *const Formula, allocator: Allocator) ![]const []const u8 {
        var names = try allocator.alloc([]const u8, self.methods.len);
        for (self.methods, 0..) |method, i| {
            names[i] = method.name;
        }
        return names;
    }
};

// ============================================================================
// Embedded formulas
// ============================================================================

const github_json = @embedFile("formulas/github.json");
const codex_json = @embedFile("formulas/codex.json");
const claude_json = @embedFile("formulas/claude.json");
const linear_json = @embedFile("formulas/linear.json");
const cloudflare_json = @embedFile("formulas/cloudflare.json");
const shopify_json = @embedFile("formulas/shopify.json");
const gitlab_json = @embedFile("formulas/gitlab.json");
const stripe_json = @embedFile("formulas/stripe.json");

var builtin_formulas_loaded = false;
var builtin_formulas: [8]FormulaOwned = undefined;

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
    builtin_formulas[3] = try loadFromJsonSlice(allocator, linear_json);
    builtin_formulas[4] = try loadFromJsonSlice(allocator, cloudflare_json);
    builtin_formulas[5] = try loadFromJsonSlice(allocator, shopify_json);
    builtin_formulas[6] = try loadFromJsonSlice(allocator, gitlab_json);
    builtin_formulas[7] = try loadFromJsonSlice(allocator, stripe_json);
}

pub fn deinitBuiltinFormulas() void {
    if (!builtin_formulas_loaded) return;
    for (&builtin_formulas) |*formula| {
        formula.deinit();
    }
    builtin_formulas_loaded = false;
}

// ============================================================================
// FormulaOwned - owns all allocated memory
// ============================================================================

pub const FormulaOwned = struct {
    allocator: Allocator,
    formula: Formula,
    parsed: json.Parsed(json.Value),
    // Track all allocations for cleanup
    methods_alloc: ?[]const MethodDef = null,
    apis_alloc: ?[]const ApiDef = null,
    clients_alloc: ?[]const Client = null,
    // Nested allocations
    string_arrays: std.ArrayListUnmanaged([]const []const u8) = .{},
    script_steps_arrays: std.ArrayListUnmanaged([]const ScriptStep) = .{},

    pub fn deinit(self: *FormulaOwned) void {
        // Free string arrays (grant_types, response_types, api.methods, client.methods, register.steps)
        for (self.string_arrays.items) |arr| {
            self.allocator.free(arr);
        }
        self.string_arrays.deinit(self.allocator);

        // Free script step arrays
        for (self.script_steps_arrays.items) |arr| {
            self.allocator.free(arr);
        }
        self.script_steps_arrays.deinit(self.allocator);

        // Free main arrays
        if (self.methods_alloc) |arr| self.allocator.free(arr);
        if (self.apis_alloc) |arr| self.allocator.free(arr);
        if (self.clients_alloc) |arr| self.allocator.free(arr);

        self.parsed.deinit();
    }

    pub fn asConst(self: *const FormulaOwned) *const Formula {
        return &self.formula;
    }
};

// ============================================================================
// JSON Parsing Helpers
// ============================================================================

fn expectString(value: json.Value) ![]const u8 {
    return switch (value) {
        .string => |s| s,
        .number_string => |s| s,
        else => return Error.InvalidField,
    };
}

fn optionalString(value: ?json.Value) !?[]const u8 {
    if (value) |v| {
        if (v == .null) return null;
        return try expectString(v);
    }
    return null;
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

fn parseScriptSteps(allocator: Allocator, value: json.Value) ![]const ScriptStep {
    const arr = switch (value) {
        .array => |a| a,
        else => return Error.InvalidField,
    };

    var slice = try allocator.alloc(ScriptStep, arr.items.len);
    errdefer allocator.free(slice);

    for (arr.items, 0..) |item, idx| {
        const obj = switch (item) {
            .object => |o| o,
            else => return Error.InvalidField,
        };

        slice[idx] = ScriptStep{
            .@"type" = try expectString(obj.get("type") orelse return Error.MissingField),
            .value = try optionalString(obj.get("value")),
            .note = try optionalString(obj.get("note")),
        };
    }

    return slice;
}

// ============================================================================
// Main Parser
// ============================================================================

pub fn loadFromJsonSlice(allocator: Allocator, slice: []const u8) !FormulaOwned {
    var parsed = try json.parseFromSlice(json.Value, allocator, slice, .{ .allocate = .alloc_always });
    errdefer parsed.deinit();

    const root = switch (parsed.value) {
        .object => |obj| obj,
        else => return Error.InvalidRootDocument,
    };

    const schema = try expectString(root.get("schema") orelse return Error.MissingField);
    if (!std.mem.eql(u8, schema, "v2")) return Error.InvalidSchema;

    const id = try expectString(root.get("id") orelse return Error.MissingField);
    const label = try expectString(root.get("label") orelse return Error.MissingField);

    var owned = FormulaOwned{
        .allocator = allocator,
        .formula = undefined,
        .parsed = parsed,
    };
    errdefer owned.deinit();

    // Parse methods (required)
    const methods_value = root.get("methods") orelse return Error.MissingField;
    const methods_obj = switch (methods_value) {
        .object => |o| o,
        else => return Error.InvalidField,
    };

    var methods = try allocator.alloc(MethodDef, methods_obj.count());
    owned.methods_alloc = methods;

    var method_idx: usize = 0;
    var methods_iter = methods_obj.iterator();
    while (methods_iter.next()) |entry| {
        const method_name = entry.key_ptr.*;
        const method_obj = switch (entry.value_ptr.*) {
            .object => |o| o,
            else => return Error.InvalidField,
        };

        var method_def = MethodDef{
            .name = method_name,
            .label = try optionalString(method_obj.get("label")),
            .scope = try optionalString(method_obj.get("scope")),
        };

        // Parse endpoints
        if (method_obj.get("endpoints")) |endpoints_value| {
            const ep_obj = switch (endpoints_value) {
                .object => |o| o,
                else => return Error.InvalidField,
            };
            method_def.endpoints = Endpoints{
                .authorize = try optionalString(ep_obj.get("authorize")),
                .token = try optionalString(ep_obj.get("token")),
                .device = try optionalString(ep_obj.get("device")),
                .registration = try optionalString(ep_obj.get("registration")),
            };
        }

        // Parse register
        if (method_obj.get("register")) |register_value| {
            const reg_obj = switch (register_value) {
                .object => |o| o,
                else => return Error.InvalidField,
            };
            const reg_url = try expectString(reg_obj.get("url") orelse return Error.MissingField);
            const reg_steps = try parseStringArray(allocator, reg_obj.get("steps") orelse return Error.MissingField);
            try owned.string_arrays.append(allocator, reg_steps);
            method_def.register = ScriptRegister{
                .url = reg_url,
                .steps = reg_steps,
            };
        }

        // Parse script (array of steps)
        if (method_obj.get("script")) |script_value| {
            const steps = try parseScriptSteps(allocator, script_value);
            try owned.script_steps_arrays.append(allocator, steps);
            method_def.script = steps;
        }

        // Parse dynamic_registration
        if (method_obj.get("dynamic_registration")) |dr_value| {
            const dr_obj = switch (dr_value) {
                .object => |o| o,
                else => return Error.InvalidField,
            };
            var dr = DynamicRegistration{
                .client_name = try optionalString(dr_obj.get("client_name")),
                .token_endpoint_auth_method = try optionalString(dr_obj.get("token_endpoint_auth_method")),
            };
            if (dr_obj.get("grant_types")) |gt| {
                const arr = try parseStringArray(allocator, gt);
                try owned.string_arrays.append(allocator, arr);
                dr.grant_types = arr;
            }
            if (dr_obj.get("response_types")) |rt| {
                const arr = try parseStringArray(allocator, rt);
                try owned.string_arrays.append(allocator, arr);
                dr.response_types = arr;
            }
            method_def.dynamic_registration = dr;
        }

        methods[method_idx] = method_def;
        method_idx += 1;
    }

    // Parse apis (required)
    const apis_value = root.get("apis") orelse return Error.MissingField;
    const apis_obj = switch (apis_value) {
        .object => |o| o,
        else => return Error.InvalidField,
    };

    var apis = try allocator.alloc(ApiDef, apis_obj.count());
    owned.apis_alloc = apis;

    var api_idx: usize = 0;
    var apis_iter = apis_obj.iterator();
    while (apis_iter.next()) |entry| {
        const api_name = entry.key_ptr.*;
        const api_obj = switch (entry.value_ptr.*) {
            .object => |o| o,
            else => return Error.InvalidField,
        };

        var api_methods: []const []const u8 = &.{};
        if (api_obj.get("methods")) |methods_val| {
            api_methods = try parseStringArray(allocator, methods_val);
            try owned.string_arrays.append(allocator, api_methods);
        }

        apis[api_idx] = ApiDef{
            .name = api_name,
            .base_url = try expectString(api_obj.get("base_url") orelse return Error.MissingField),
            .auth_header = try expectString(api_obj.get("auth_header") orelse return Error.MissingField),
            .docs_url = try optionalString(api_obj.get("docs_url")),
            .spec_url = try optionalString(api_obj.get("spec_url")),
            .spec_type = try optionalString(api_obj.get("spec_type")),
            .methods = api_methods,
        };
        api_idx += 1;
    }

    // Parse clients (optional)
    var clients: ?[]const Client = null;
    if (root.get("clients")) |clients_value| {
        const clients_arr = switch (clients_value) {
            .array => |a| a,
            else => return Error.InvalidField,
        };

        var clients_slice = try allocator.alloc(Client, clients_arr.items.len);
        owned.clients_alloc = clients_slice;

        for (clients_arr.items, 0..) |item, idx| {
            const client_obj = switch (item) {
                .object => |o| o,
                else => return Error.InvalidField,
            };

            var client_methods: ?[]const []const u8 = null;
            if (client_obj.get("methods")) |m| {
                if (m != .null) {
                    client_methods = try parseStringArray(allocator, m);
                    try owned.string_arrays.append(allocator, client_methods.?);
                }
            }

            clients_slice[idx] = Client{
                .name = try expectString(client_obj.get("name") orelse return Error.MissingField),
                .id = try expectString(client_obj.get("id") orelse return Error.MissingField),
                .secret = try optionalString(client_obj.get("secret")),
                .source = try optionalString(client_obj.get("source")),
                .methods = client_methods,
                .redirect_uri = try optionalString(client_obj.get("redirect_uri")),
            };
        }
        clients = clients_slice;
    }

    // Parse identity (optional)
    var identity: ?Identity = null;
    if (root.get("identity")) |identity_value| {
        const identity_obj = switch (identity_value) {
            .object => |o| o,
            else => return Error.InvalidField,
        };
        identity = Identity{
            .label = try optionalString(identity_obj.get("label")),
            .hint = try optionalString(identity_obj.get("hint")),
        };
    }

    owned.formula = Formula{
        .schema = schema,
        .id = id,
        .label = label,
        .methods = methods,
        .apis = apis,
        .clients = clients,
        .identity = identity,
    };

    return owned;
}

pub fn loadFromPath(allocator: Allocator, path: []const u8) !FormulaOwned {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const buffer = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(buffer);

    return loadFromJsonSlice(allocator, buffer);
}

// ============================================================================
// Tests
// ============================================================================

test "FormulaOwned: parse v2 formula without leaks" {
    const allocator = std.testing.allocator;

    const v2_json =
        \\{
        \\  "schema": "v2",
        \\  "id": "test",
        \\  "label": "Test Provider",
        \\  "methods": {
        \\    "oauth": {
        \\      "label": "OAuth",
        \\      "endpoints": {
        \\        "authorize": "https://test.com/authorize",
        \\        "token": "https://test.com/token"
        \\      },
        \\      "scope": "read write",
        \\      "script": [
        \\        { "type": "open_url", "value": "{authorize_url}" },
        \\        { "type": "wait_for_callback" }
        \\      ]
        \\    }
        \\  },
        \\  "apis": {
        \\    "rest": {
        \\      "base_url": "https://api.test.com",
        \\      "auth_header": "Authorization: Bearer {token}",
        \\      "methods": ["oauth"]
        \\    }
        \\  }
        \\}
    ;

    var owned = try loadFromJsonSlice(allocator, v2_json);
    defer owned.deinit();

    try std.testing.expectEqualStrings("v2", owned.formula.schema);
    try std.testing.expectEqualStrings("test", owned.formula.id);
    try std.testing.expectEqual(@as(usize, 1), owned.formula.methods.len);

    const method = owned.formula.getMethod("oauth");
    try std.testing.expect(method != null);
    try std.testing.expectEqualStrings("OAuth", method.?.label.?);
    try std.testing.expect(method.?.isAuthorizationCode());

    const api = owned.formula.getApi("rest");
    try std.testing.expect(api != null);
    try std.testing.expectEqualStrings("https://api.test.com", api.?.base_url);
}

test "FormulaOwned: parse v2 formula with clients without leaks" {
    const allocator = std.testing.allocator;

    const v2_json =
        \\{
        \\  "schema": "v2",
        \\  "id": "github",
        \\  "label": "GitHub",
        \\  "clients": [
        \\    {
        \\      "name": "gh-cli",
        \\      "id": "abc123",
        \\      "secret": "secret456",
        \\      "source": "https://github.com/cli/cli",
        \\      "methods": ["device_code"]
        \\    }
        \\  ],
        \\  "methods": {
        \\    "device_code": {
        \\      "endpoints": {
        \\        "device": "https://github.com/login/device/code",
        \\        "token": "https://github.com/login/oauth/access_token"
        \\      },
        \\      "scope": "repo"
        \\    }
        \\  },
        \\  "apis": {
        \\    "rest": {
        \\      "base_url": "https://api.github.com",
        \\      "auth_header": "Authorization: Bearer {token}",
        \\      "methods": ["device_code"]
        \\    }
        \\  }
        \\}
    ;

    var owned = try loadFromJsonSlice(allocator, v2_json);
    defer owned.deinit();

    const client = owned.formula.getDefaultClient();
    try std.testing.expect(client != null);
    try std.testing.expectEqualStrings("gh-cli", client.?.name);
    try std.testing.expectEqualStrings("abc123", client.?.id);

    const method = owned.formula.getMethod("device_code");
    try std.testing.expect(method != null);
    try std.testing.expect(method.?.isDeviceCode());
}

test "FormulaOwned: parse v2 formula with identity without leaks" {
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
        \\    "api_key": {
        \\      "script": [
        \\        { "type": "copy_key", "note": "Paste your API key" }
        \\      ]
        \\    }
        \\  },
        \\  "apis": {
        \\    "graphql": {
        \\      "base_url": "https://api.linear.app/graphql",
        \\      "auth_header": "Authorization: {token}",
        \\      "methods": ["api_key"]
        \\    }
        \\  }
        \\}
    ;

    var owned = try loadFromJsonSlice(allocator, v2_json);
    defer owned.deinit();

    try std.testing.expect(owned.formula.identity != null);
    try std.testing.expectEqualStrings("Workspace", owned.formula.identity.?.label.?);
    try std.testing.expectEqualStrings("Use the workspace slug", owned.formula.identity.?.hint.?);

    const method = owned.formula.getMethod("api_key");
    try std.testing.expect(method != null);
    try std.testing.expect(method.?.isApiKey());
}

test "FormulaOwned: parse v2 formula with dynamic registration without leaks" {
    const allocator = std.testing.allocator;

    const v2_json =
        \\{
        \\  "schema": "v2",
        \\  "id": "mcp-provider",
        \\  "label": "MCP Provider",
        \\  "methods": {
        \\    "mcp_oauth": {
        \\      "endpoints": {
        \\        "registration": "https://mcp.example.com/register",
        \\        "authorize": "https://mcp.example.com/authorize",
        \\        "token": "https://mcp.example.com/token"
        \\      },
        \\      "dynamic_registration": {
        \\        "client_name": "schlussel",
        \\        "grant_types": ["authorization_code", "refresh_token"],
        \\        "response_types": ["code"],
        \\        "token_endpoint_auth_method": "none"
        \\      },
        \\      "script": [
        \\        { "type": "open_url", "value": "{authorize_url}" },
        \\        { "type": "wait_for_callback" }
        \\      ]
        \\    }
        \\  },
        \\  "apis": {
        \\    "mcp": {
        \\      "base_url": "https://mcp.example.com/mcp",
        \\      "auth_header": "Authorization: Bearer {token}",
        \\      "methods": ["mcp_oauth"]
        \\    }
        \\  }
        \\}
    ;

    var owned = try loadFromJsonSlice(allocator, v2_json);
    defer owned.deinit();

    const method = owned.formula.getMethod("mcp_oauth");
    try std.testing.expect(method != null);
    try std.testing.expect(method.?.usesDynamicRegistration());
    try std.testing.expectEqualStrings("schlussel", method.?.dynamic_registration.?.client_name.?);
    try std.testing.expectEqual(@as(usize, 2), method.?.dynamic_registration.?.grant_types.?.len);
}

test "FormulaOwned: getDefaultClientForMethod filters by method" {
    const allocator = std.testing.allocator;

    const v2_json =
        \\{
        \\  "schema": "v2",
        \\  "id": "multi-client",
        \\  "label": "Multi Client",
        \\  "clients": [
        \\    {
        \\      "name": "device-only",
        \\      "id": "device-id",
        \\      "methods": ["device_code"]
        \\    },
        \\    {
        \\      "name": "oauth-only",
        \\      "id": "oauth-id",
        \\      "methods": ["oauth"]
        \\    }
        \\  ],
        \\  "methods": {
        \\    "device_code": {
        \\      "endpoints": {
        \\        "device": "https://test.com/device",
        \\        "token": "https://test.com/token"
        \\      }
        \\    },
        \\    "oauth": {
        \\      "endpoints": {
        \\        "authorize": "https://test.com/authorize",
        \\        "token": "https://test.com/token"
        \\      }
        \\    }
        \\  },
        \\  "apis": {
        \\    "api": {
        \\      "base_url": "https://api.test.com",
        \\      "auth_header": "Authorization: Bearer {token}",
        \\      "methods": ["device_code", "oauth"]
        \\    }
        \\  }
        \\}
    ;

    var owned = try loadFromJsonSlice(allocator, v2_json);
    defer owned.deinit();

    const device_client = owned.formula.getDefaultClientForMethod("device_code");
    try std.testing.expect(device_client != null);
    try std.testing.expectEqualStrings("device-id", device_client.?.id);

    const oauth_client = owned.formula.getDefaultClientForMethod("oauth");
    try std.testing.expect(oauth_client != null);
    try std.testing.expectEqualStrings("oauth-id", oauth_client.?.id);
}

test "FormulaOwned: error on v1 schema" {
    const allocator = std.testing.allocator;

    const v1_json =
        \\{
        \\  "schema": "v1",
        \\  "id": "test",
        \\  "label": "Test",
        \\  "methods": ["device_code"]
        \\}
    ;

    const result = loadFromJsonSlice(allocator, v1_json);
    try std.testing.expectError(Error.InvalidSchema, result);
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
    try std.testing.expect(github == github2);

    // Non-existent formula
    const nonexistent = try findById(allocator, "nonexistent");
    try std.testing.expect(nonexistent == null);

    // Clean up
    deinitBuiltinFormulas();
}
