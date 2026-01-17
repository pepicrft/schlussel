# Next: Local Authentication Runtime for Agents

Schlussel is **the local authentication runtime for agents**. Agents need to authenticate against external platforms, but authentication is complex: OAuth flows require user interaction, tokens expire and need refreshing, multiple agents might race to refresh the same token, and credentials need secure storage. Schlussel handles all of this through a CLI that agents invoke directly.

## What We Have Today

The foundation is solid:

- **Formula system**: JSON recipes describing how to authenticate (OAuth2 flows, API keys, PATs)
- **Declarative scripts**: Machine-readable steps agents can present to users
- **Session management**: CRUD for tokens with secure OS storage (Keychain, Credential Manager, libsecret)
- **Locking**: Cross-process locks preventing refresh race conditions
- **CLI**: `schlussel script`, `schlussel run`, `schlussel token` commands
- **Identity support**: `--identity` flag for multiple accounts per platform

## What's Next

### 1. Formula Directory Expansion

A growing library of formulas for popular platforms. Community-contributed, version-controlled.

**Priority formulas to add:**
- Linear
- Notion
- Slack
- Figma
- Airtable
- Stripe
- Vercel
- Fly.io
- AWS (STS)
- Google Cloud

**Formula distribution:**
- Built-in formulas embedded in the binary (current approach)
- Remote formula registry (future: `schlussel formula add linear`)
- Local formula directories for custom/private platforms

### 2. Formula Schema Iteration

Review the current schema for gaps:

- Are all common auth patterns covered?
- Do we need better support for API key authentication variants?
- Should formulas include metadata like documentation URLs, rate limits?
- How do we handle platforms with regional endpoints?
- Token introspection hints (how to verify a token is still valid)?

**API metadata for agents:**
Formulas should capture everything an agent needs to use the API after authentication:

- `api.base_url` - The API base URL (e.g., `https://api.linear.app/graphql`)
- `api.auth_header` - How to pass the token (e.g., `Authorization: Bearer {token}`)
- `api.docs_url` - Link to API documentation

With this, an agent has everything it needs: `schlussel token get linear` + `curl` = full API access.

**Schema v2 - method-centric design:**

Current schema mixes method-specific concerns at the formula root. Cleaner approach: nest everything under methods.

```json
{
  "schema": "v2",
  "id": "linear",
  "label": "Linear",
  "api": {
    "base_url": "https://api.linear.app/graphql",
    "auth_header": "Authorization: Bearer {token}",
    "docs_url": "https://developers.linear.app/docs"
  },
  "methods": {
    "authorization_code": {
      "label": "OAuth (User)",
      "endpoints": {
        "authorize": "https://linear.app/oauth/authorize",
        "token": "https://api.linear.app/oauth/token"
      },
      "scope": "read write",
      "public_clients": [
        {
          "name": "linear-vscode",
          "id": "3117bb53c858872ff5cd4f9e0b3d0b5d",
          "secret": "2cafd5d87b5fab6937ea3e157504dbd3",
          "source": "https://github.com/linear/linear-vscode-connect-extension"
        }
      ],
      "script": {
        "register": {
          "url": "https://linear.app/settings/api/applications/new",
          "steps": ["Create OAuth app", "Set redirect URI", "Copy credentials"]
        },
        "steps": [
          { "type": "open_url", "value": "{authorize_url}" },
          { "type": "wait_for_callback" }
        ]
      }
    },
    "api_key": {
      "label": "API Key",
      "script": {
        "register": {
          "url": "https://linear.app/settings/api",
          "steps": ["Create a personal API key", "Copy the key"]
        },
        "steps": [
          { "type": "copy_key", "note": "Paste your API key" }
        ]
      }
    }
  },
  "identity": {
    "label": "Workspace",
    "hint": "Use the workspace slug (e.g., acme)"
  }
}
```

**Key changes:**
- `endpoints`, `scope`, `public_clients`, `script` all scoped to their method
- `api` block for post-auth API usage (base URL, auth header format, docs)
- `identity` for UI hints only (optional)
- Storage key is conventional: `{formula_id}:{method}:{identity}` - not configurable

### 3. CLI Ergonomics for Agents

The CLI is the interface. Make it agent-friendly:

- Machine-readable JSON output everywhere (`--json` flags)
- Clear exit codes for different failure modes
- Stdin support for non-interactive flows
- Better error messages that agents can parse and act on

### 4. Website + Formula API

Move the site to a Cloudflare Worker with Hono.js:

- Serve the static site
- API to query formulas remotely (`GET /api/formulas`, `GET /api/formulas/:id`)
- Enables `schlussel formula fetch linear` to pull from the registry
- Formulas stay in the repo, API serves them dynamically

### 5. Documentation

- Agent integration guide (how to call Schlussel from your agent)
- Formula authoring guide (how to add a new platform)
- Troubleshooting common auth failures

## Design Principles

1. **Local-first**: Credentials never leave the machine. Schlussel is not a cloud service.
2. **CLI-native**: Agents shell out to Schlussel. No SDKs, no daemons, no servers.
3. **Formula-driven**: All platform knowledge lives in portable JSON recipes.
4. **Secure by default**: OS credential managers, PKCE, locked refreshes.
5. **Zero-config for common cases**: Built-in formulas with public clients.

## Open Questions

- How do we handle platforms that require app-specific client credentials?
- Should formulas include rate limit hints for token endpoints?
- How do we version formulas when platform APIs change?
- Remote formula registry: git repo? HTTP API? Something else?
