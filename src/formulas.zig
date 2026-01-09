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

pub const Quirks = struct {
    dynamic_registration_endpoint: ?[]const u8,
    token_response: ?[]const u8,
    extra_response_fields: ?[]const []const u8,
};

pub const Formula = struct {
    id: []const u8,
    label: []const u8,
    flows: []const Flow,
    authorization_endpoint: []const u8,
    token_endpoint: []const u8,
    device_authorization_endpoint: ?[]const u8,
    scope: ?[]const u8,
    onboarding: Onboarding,
    quirks: ?Quirks,
};

const builtinFormulas = [_]Formula{
    .{
        .id = "github",
        .label = "GitHub",
        .flows = &_GitHubFlows,
        .authorization_endpoint = "https://github.com/login/oauth/authorize",
        .token_endpoint = "https://github.com/login/oauth/access_token",
        .device_authorization_endpoint = "https://github.com/login/device/code",
        .scope = null,
        .onboarding = Onboarding{
            .register_url = "https://github.com/settings/developers",
            .steps = &_GitHubSteps,
        },
        .quirks = null,
    },
    .{
        .id = "google",
        .label = "Google",
        .flows = &_GoogleFlows,
        .authorization_endpoint = "https://accounts.google.com/o/oauth2/v2/auth",
        .token_endpoint = "https://oauth2.googleapis.com/token",
        .device_authorization_endpoint = "https://oauth2.googleapis.com/device/code",
        .scope = null,
        .onboarding = Onboarding{
            .register_url = "https://console.developers.google.com/apis/credentials",
            .steps = &_GoogleSteps,
        },
        .quirks = null,
    },
    .{
        .id = "microsoft",
        .label = "Microsoft Entra",
        .flows = &_MicrosoftFlows,
        .authorization_endpoint = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
        .token_endpoint = "https://login.microsoftonline.com/common/oauth2/v2.0/token",
        .device_authorization_endpoint = "https://login.microsoftonline.com/common/oauth2/v2.0/devicecode",
        .scope = null,
        .onboarding = Onboarding{
            .register_url = "https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps/ApplicationsListBlade",
            .steps = &_MicrosoftSteps,
        },
        .quirks = null,
    },
    .{
        .id = "gitlab",
        .label = "GitLab",
        .flows = &_GitLabFlows,
        .authorization_endpoint = "https://gitlab.com/oauth/authorize",
        .token_endpoint = "https://gitlab.com/oauth/token",
        .device_authorization_endpoint = null,
        .scope = null,
        .onboarding = Onboarding{
            .register_url = "https://gitlab.com/-/profile/applications",
            .steps = &_GitLabSteps,
        },
        .quirks = null,
    },
    .{
        .id = "tuist",
        .label = "Tuist Cloud",
        .flows = &_TuistFlows,
        .authorization_endpoint = "https://tuist.io/oauth/authorize",
        .token_endpoint = "https://tuist.io/oauth/token",
        .device_authorization_endpoint = null,
        .scope = null,
        .onboarding = Onboarding{
            .register_url = "https://tuist.io/settings/oauth",
            .steps = &_TuistSteps,
        },
        .quirks = Quirks{
            .dynamic_registration_endpoint = "https://tuist.io/oauth/register",
            .token_response = "nested",
            .extra_response_fields = &_TuistExtraFields,
        },
    },
    .{
        .id = "slack",
        .label = "Slack",
        .flows = &_SlackFlows,
        .authorization_endpoint = "https://slack.com/oauth/v2/authorize",
        .token_endpoint = "https://slack.com/api/oauth.v2.access",
        .device_authorization_endpoint = null,
        .scope = null,
        .onboarding = Onboarding{
            .register_url = "https://api.slack.com/apps",
            .steps = &_SlackSteps,
        },
        .quirks = Quirks{
            .dynamic_registration_endpoint = null,
            .token_response = "nested",
            .extra_response_fields = &_SlackExtraFields,
        },
    },
};

const _GitHubFlows = [_]Flow{ .authorization_code, .device_code };
const _GoogleFlows = [_]Flow{ .authorization_code, .device_code };
const _MicrosoftFlows = [_]Flow{ .authorization_code, .device_code };
const _GitLabFlows = [_]Flow{.authorization_code};
const _TuistFlows = [_]Flow{ .authorization_code, .device_code };
const _SlackFlows = [_]Flow{.authorization_code};

const _ConciseSteps = [_][]const u8;

const _GitHubSteps = &_ConciseSteps{
    "Create a new OAuth app under your organization.",
    "Set the callback URL to http://127.0.0.1/callback.",
    "Copy the client ID/secret into your configuration.",
};
const _GoogleSteps = &_ConciseSteps{
    "Create OAuth credentials for your application.",
    "Add http://127.0.0.1/callback as an authorized redirect URI.",
    "Enable the necessary Google APIs.",
};
const _MicrosoftSteps = &_ConciseSteps{
    "Register your CLI as a multi-tenant application in Microsoft Entra.",
    "Add http://127.0.0.1/callback to the redirect URIs.",
    "Grant Graph scopes or other required APIs.",
};
const _GitLabSteps = &_ConciseSteps{
    "Create a new application for your CLI.",
    "Provide a redirect URI such as http://127.0.0.1/callback.",
    "Keep the client secret encrypted and rotate when needed.",
};
const _TuistSteps = &_ConciseSteps{
    "Create an OAuth client in Tuist Cloud workspace settings.",
    "Set the redirect URI that matches your CLI callback.",
    "Register the scopes your workflows require and copy credentials.",
};
const _SlackSteps = &_ConciseSteps{
    "Create a Slack app and enable OAuth & Permissions.",
    "Add your redirect URI and install the app.",
    "Copy the client ID and secret into Schlussel.",
};

const _TuistExtraFields = &_ConciseSteps{"project_id"};
const _SlackExtraFields = &_ConciseSteps{"incoming_webhook"};

pub fn findById(id: []const u8) ?*const Formula {
    for (builtinFormulas) |formula| {
        if (std.mem.eql(u8, formula.id, id)) return &formula;
    }
    return null;
}

pub const FormulaOwned = struct {
    allocator: Allocator,
    formula: Formula,
    flows_alloc: ?[]const Flow,
    steps_alloc: ?[]const []const u8,
    extra_fields_alloc: ?[]const []const u8,
    parsed: json.Parsed(json.Value),

    pub fn deinit(self: *FormulaOwned) void {
        if (self.flows_alloc) |arr| self.allocator.free(arr);
        if (self.steps_alloc) |arr| self.allocator.free(arr);
        if (self.extra_fields_alloc) |arr| self.allocator.free(arr);
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
    for (arr.items.len) |idx| {
        const item = arr.items[idx];
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
    for (arr.items.len) |idx| {
        const item = arr.items[idx];
        const text = try expectString(item);
        slice[idx] = flowFromString(text) orelse return Error.InvalidFlow;
    }
    return slice;
}

pub fn loadFromPath(allocator: Allocator, path: []const u8) !FormulaOwned {
    const file = try std.fs.cwd().openFile(path, .{ .read = true });
    defer file.close();

    var buffer = try file.readToEndAlloc(allocator, 4096);
    errdefer allocator.free(buffer);

    var parsed = try json.parseFromSlice(json.Value, allocator, buffer, .{ .allocate = .alloc_always });
    errdefer parsed.deinit();

    allocator.free(buffer);

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

    const onboarding_value = root.get("onboarding") orelse return Error.MissingField;
    const onboarding_obj = switch (onboarding_value) {
        .object => |o| o,
        else => return Error.InvalidField,
    };

    const register_url = try expectString(onboarding_obj.get("register_url") orelse return Error.MissingField);
    const steps = try parseStringArray(allocator, onboarding_obj.get("steps") orelse return Error.MissingField);

    const scope = try optionalString(root.get("scope"));

    var quirks: ?Quirks = null;
    if (root.get("quirks")) |quirks_value| {
        const quirks_obj = switch (quirks_value) {
            .object => |o| o,
            else => return Error.InvalidField,
        };

        const dynamic_endpoint = try optionalString(quirks_obj.get("dynamic_registration_endpoint"));
        const token_response = try optionalString(quirks_obj.get("token_response"));
        const extra_fields = try optionalStringArray(allocator, quirks_obj.get("extra_response_fields"));

        quirks = Quirks{
            .dynamic_registration_endpoint = dynamic_endpoint,
            .token_response = token_response,
            .extra_response_fields = extra_fields,
        };
    }

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
            .onboarding = Onboarding{
                .register_url = register_url,
                .steps = steps,
            },
            .quirks = quirks,
        },
        .flows_alloc = flows,
        .steps_alloc = steps,
        .extra_fields_alloc = if (quirks) |q| q.extra_response_fields else null,
        .parsed = parsed,
    };
}
