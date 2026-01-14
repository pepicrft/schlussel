# Schlussel

**Auth runtime for agents and CLI applications** - Written in Zig, works everywhere

OAuth authentication made simple for command-line tools. No more copying tokens or managing credentials manually!

---

## Features

**Multiple OAuth Methods**
- Device Code Flow (perfect for CLI!)
- Authorization Code Flow with PKCE
- Automatic browser handling

**Interaction Plans**
- Structured steps agents can render
- Resolved plan context for device codes and callbacks
- Execute plans via CLI or FFI

**Secure by Default**
- OS credential manager integration (Keychain/Credential Manager)
- Cross-process token refresh locking
- Automatic token refresh

**Developer Friendly**
- Provider presets (GitHub, Google, Microsoft, GitLab, Tuist)
- One-line configuration
- Automatic expiration handling

**Cross-Platform**
- Linux, macOS, Windows
- x86_64 and ARM64

---

## Quick Start

### Installation

Add as a Zig dependency in your `build.zig.zon`:
```zig
.dependencies = .{
    .schlussel = .{
        .url = "https://github.com/pepicrft/schlussel/archive/refs/heads/main.tar.gz",
    },
},
```

Then in your `build.zig`:
```zig
const schlussel = b.dependency("schlussel", .{});
exe.root_module.addImport("schlussel", schlussel.module("schlussel"));
```

### Authenticate with GitHub

```zig
const std = @import("std");
const schlussel = @import("schlussel");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create storage and client
    var storage = schlussel.MemoryStorage.init(allocator);
    defer storage.deinit();

    const config = schlussel.OAuthConfig.github("your-client-id", "repo user");
    var client = schlussel.OAuthClient.init(allocator, config, storage.storage());
    defer client.deinit();

    // That's it! Opens browser, handles OAuth, returns token
    var token = try client.authorizeDevice();
    defer token.deinit();

    std.debug.print("Access token: {s}\n", .{token.access_token});
}
```

### Generate and Run a Plan

```bash
# Create a resolved plan for device code
schlussel plan github --method device_code --resolve > plan.json

# Execute the plan and store the token
schlussel run github --plan-json plan.json
```

---

## Use Cases

- CLI tools that need GitHub/GitLab API access
- Build tools that integrate with cloud services
- Developer tools with OAuth authentication
- Cross-platform desktop applications
- CI/CD tools with secure credential management

---

## Architecture

```
+-------------------+
|   Your CLI App    |
+---------+---------+
          |
     +----v-----+
     | Schlussel|
     +----+-----+
          |
     +----v-----------------------------+
     |  Storage Backend                 |
     +----------------------------------+
     | SecureStorage (OS Keyring)       | <- Recommended
     | FileStorage   (JSON files)       |
     | MemoryStorage (In-memory)        |
     +----------------------------------+
```

---

## Highlights

### Secure by Default
Tokens stored in **OS credential manager** (Keychain on macOS, Credential Manager on Windows, libsecret on Linux)

### Provider Presets
```zig
schlussel.OAuthConfig.github("id", "repo")           // GitHub
schlussel.OAuthConfig.google("id", "email")          // Google
schlussel.OAuthConfig.microsoft("id", "common", null) // Microsoft
schlussel.OAuthConfig.gitlab("id", null, null)       // GitLab
schlussel.OAuthConfig.tuist("id", null, null)        // Tuist
```

### Dynamic Client Registration
Register clients dynamically with OAuth servers that support RFC 7591. For read/update/delete,
initialize `DynamicRegistration` with the `registration_client_uri` returned by the server.

### Automatic Token Refresh
```zig
var refresher = schlussel.TokenRefresher.init(allocator, &client);
defer refresher.deinit();

var token = try refresher.getValidToken("key");
defer token.deinit();
// Auto-refreshes if expired!
```

### Cross-Process Safe
Multiple processes can safely refresh the same token without race conditions

---

## Examples

Check out [examples/](examples/) for working code:

- [GitHub Device Flow](examples/github_device_flow.zig)
- [Automatic Refresh](examples/automatic_refresh.zig)

## Documentation

- [Formula schema](docs/formula.md)
- [Interaction plans](docs/plan.md)

---

## Building

```bash
# Build
zig build

# Run tests
zig build test

# Format code
zig fmt src/
```

---

## Contributing

Contributions welcome! Please ensure:
- Tests pass: `zig build test`
- Code formatted: `zig fmt --check src/`

---

## License

See [LICENSE](LICENSE) for details.

---

**Made with love by the Tuist team**
