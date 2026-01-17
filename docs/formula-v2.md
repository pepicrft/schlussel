# Formula Schema v2

Schlussel formulas describe how to authenticate against a platform. v2 keeps auth methods at the root and lets APIs declare which methods produce valid tokens for them.

## Design Principles

1. **Methods at root**: Auth methods defined once, APIs reference which ones they accept
2. **Shared clients**: Public clients defined once, with optional method restrictions
3. **API-to-method mapping**: Each API declares which auth methods produce valid tokens
4. **Conventional storage**: Keys are always `{formula_id}:{method}:{identity}` - not configurable

## Shape

```json
{
  "schema": "v2",
  "id": "linear",
  "label": "Linear",

  "clients": [
    {
      "name": "linear-vscode",
      "id": "3117bb53c858872ff5cd4f9e0b3d0b5d",
      "secret": "2cafd5d87b5fab6937ea3e157504dbd3",
      "source": "https://github.com/linear/linear-vscode-connect-extension",
      "methods": ["oauth"]
    }
  ],

  "identity": {
    "label": "Workspace",
    "hint": "Use the workspace slug (e.g., acme)"
  },

  "methods": {
    "oauth": {
      "label": "OAuth",
      "endpoints": {
        "authorize": "https://linear.app/oauth/authorize",
        "token": "https://api.linear.app/oauth/token"
      },
      "scope": "read write",
      "register": {
        "url": "https://linear.app/settings/api/applications/new",
        "steps": [
          "Create a new OAuth application",
          "Set redirect URI to http://127.0.0.1:0/callback",
          "Copy the client ID and secret"
        ]
      },
      "script": [
        { "type": "open_url", "value": "{authorize_url}" },
        { "type": "wait_for_callback" }
      ]
    },
    "api_key": {
      "label": "API Key",
      "register": {
        "url": "https://linear.app/settings/api",
        "steps": [
          "Go to Settings > API",
          "Create a personal API key",
          "Copy the key"
        ]
      },
      "script": [
        { "type": "copy_key", "note": "Paste your Linear API key" }
      ]
    },
    "mcp_oauth": {
      "label": "MCP OAuth",
      "endpoints": {
        "registration": "https://mcp.linear.app/register",
        "authorize": "https://mcp.linear.app/authorize",
        "token": "https://mcp.linear.app/token"
      },
      "dynamic_registration": {
        "client_name": "schlussel",
        "grant_types": ["authorization_code", "refresh_token"],
        "response_types": ["code"],
        "token_endpoint_auth_method": "none"
      },
      "script": [
        { "type": "open_url", "value": "{authorize_url}" },
        { "type": "wait_for_callback" }
      ]
    }
  },

  "apis": {
    "graphql": {
      "base_url": "https://api.linear.app/graphql",
      "auth_header": "Authorization: {token}",
      "docs_url": "https://developers.linear.app/docs",
      "spec_url": "https://api.linear.app/graphql",
      "spec_type": "graphql",
      "methods": ["oauth", "api_key"]
    },
    "mcp": {
      "base_url": "https://mcp.linear.app/mcp",
      "auth_header": "Authorization: Bearer {token}",
      "docs_url": "https://linear.app/docs/mcp",
      "methods": ["mcp_oauth"]
    }
  }
}
```

## Root Fields

### `schema` (required)
Version identifier. Must be `"v2"`.

### `id` (required)
Unique identifier for the formula. Used in CLI commands and storage keys.
Examples: `github`, `linear`, `slack`

### `label` (required)
Human-readable name for display.

### `clients` (optional)
Public OAuth clients that can be used without user registration:

```json
[
  {
    "name": "gh-cli",
    "id": "178c6fc778ccc68e1d6a",
    "secret": "34ddeff2b558a23d38fba8a6de74f086ede1cc0b",
    "source": "https://github.com/cli/cli",
    "methods": ["oauth"]
  }
]
```

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Identifier for the client |
| `id` | Yes | OAuth client ID |
| `secret` | No | OAuth client secret (for confidential clients) |
| `source` | No | URL where this client ID was found |
| `methods` | No | Which methods this client supports (default: all OAuth methods) |

### `identity` (optional)
UI hints for when users have multiple accounts/workspaces:

| Field | Description | Example |
|-------|-------------|---------|
| `label` | What to call the identity | `Workspace`, `Organization`, `Account` |
| `hint` | Help text for the user | `Use the workspace slug (e.g., acme)` |

### `methods` (required)
Object where keys are method names and values are method configurations.

Method names are formula-specific identifiers (e.g., `oauth`, `api_key`, `mcp_oauth`). The configuration determines the auth flow type based on which fields are present:

- Has `endpoints.authorize` + `endpoints.token` → OAuth Authorization Code flow
- Has `endpoints.device` + `endpoints.token` → OAuth Device Code flow
- Has `dynamic_registration` → OAuth with RFC 7591 dynamic registration
- Has only `script` with `copy_key` → API key / PAT flow

### `apis` (required)
Named API endpoints with their auth requirements:

```json
{
  "graphql": {
    "base_url": "https://api.linear.app/graphql",
    "auth_header": "Authorization: {token}",
    "docs_url": "https://developers.linear.app/docs",
    "spec_url": "https://api.linear.app/graphql",
    "spec_type": "graphql",
    "methods": ["oauth", "api_key"]
  }
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `base_url` | Yes | API base URL |
| `auth_header` | Yes | How to pass the token (`{token}` placeholder) |
| `methods` | Yes | Which auth methods produce valid tokens for this API |
| `docs_url` | No | Link to API documentation |
| `spec_url` | No | Link to machine-readable spec (OpenAPI, GraphQL) |
| `spec_type` | No | Type of spec: `openapi`, `graphql`, `asyncapi` |

## Method Fields

### `label` (optional)
Human-readable name for the method.

### `endpoints` (required for OAuth methods)

| Field | Description |
|-------|-------------|
| `authorize` | Authorization endpoint (for auth code flow) |
| `token` | Token endpoint |
| `device` | Device authorization endpoint (for device code flow) |
| `registration` | RFC 7591 dynamic registration endpoint |

### `scope` (optional)
Space-separated OAuth scopes.

### `dynamic_registration` (for methods using RFC 7591)

```json
{
  "client_name": "schlussel",
  "grant_types": ["authorization_code", "refresh_token"],
  "response_types": ["code"],
  "token_endpoint_auth_method": "none"
}
```

Schlussel registers a client dynamically on first use and stores the `client_id`.

### `register` (optional)
Instructions for users who need to create their own OAuth app or API key:

```json
{
  "url": "https://linear.app/settings/api/applications/new",
  "steps": [
    "Create a new OAuth application",
    "Set redirect URI to http://127.0.0.1:0/callback",
    "Copy the client ID and secret"
  ]
}
```

### `script` (required)
Array of steps that guide the user through authentication:

| Type | Description | Value |
|------|-------------|-------|
| `open_url` | User should open a URL | URL or `{placeholder}` |
| `enter_code` | User should enter a code | Code or `{user_code}` |
| `copy_key` | User should paste an API key | - |
| `wait_for_callback` | Wait for OAuth callback | - |
| `wait_for_token` | Poll for device code completion | - |

#### Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{authorize_url}` | Full authorization URL with params |
| `{verification_uri}` | URL to enter device code |
| `{verification_uri_complete}` | URL with code pre-filled |
| `{user_code}` | Code user enters |

## Storage

Storage keys are conventional:

```
{formula_id}:{method}:{identity}
```

Examples:
- `linear:oauth:acme` - Linear OAuth token for "acme" workspace
- `linear:mcp_oauth:acme` - Linear MCP token for "acme" workspace
- `github:oauth:personal` - GitHub token for "personal" identity

## Examples

### GitHub

```json
{
  "schema": "v2",
  "id": "github",
  "label": "GitHub",
  "clients": [
    {
      "name": "gh-cli",
      "id": "178c6fc778ccc68e1d6a",
      "secret": "34ddeff2b558a23d38fba8a6de74f086ede1cc0b",
      "source": "https://github.com/cli/cli",
      "methods": ["oauth", "device"]
    }
  ],
  "identity": {
    "label": "Account",
    "hint": "e.g., personal, work"
  },
  "methods": {
    "device": {
      "label": "OAuth (Device)",
      "endpoints": {
        "device": "https://github.com/login/device/code",
        "token": "https://github.com/login/oauth/access_token"
      },
      "scope": "repo read:org gist",
      "script": [
        { "type": "open_url", "value": "{verification_uri}" },
        { "type": "enter_code", "value": "{user_code}" },
        { "type": "wait_for_token" }
      ]
    },
    "oauth": {
      "label": "OAuth (Browser)",
      "endpoints": {
        "authorize": "https://github.com/login/oauth/authorize",
        "token": "https://github.com/login/oauth/access_token"
      },
      "scope": "repo read:org gist",
      "script": [
        { "type": "open_url", "value": "{authorize_url}" },
        { "type": "wait_for_callback" }
      ]
    },
    "pat": {
      "label": "Personal Access Token",
      "register": {
        "url": "https://github.com/settings/tokens/new",
        "steps": [
          "Go to Settings > Developer settings > Personal access tokens",
          "Generate a new token with required scopes",
          "Copy the token"
        ]
      },
      "script": [
        { "type": "copy_key", "note": "Paste your GitHub personal access token" }
      ]
    }
  },
  "apis": {
    "rest": {
      "base_url": "https://api.github.com",
      "auth_header": "Authorization: Bearer {token}",
      "docs_url": "https://docs.github.com/en/rest",
      "spec_url": "https://raw.githubusercontent.com/github/rest-api-description/main/descriptions/api.github.com/api.github.com.json",
      "spec_type": "openapi",
      "methods": ["oauth", "device", "pat"]
    },
    "graphql": {
      "base_url": "https://api.github.com/graphql",
      "auth_header": "Authorization: Bearer {token}",
      "docs_url": "https://docs.github.com/en/graphql",
      "spec_url": "https://api.github.com/graphql",
      "spec_type": "graphql",
      "methods": ["oauth", "device", "pat"]
    }
  }
}
```

### Stripe (API key only)

```json
{
  "schema": "v2",
  "id": "stripe",
  "label": "Stripe",
  "methods": {
    "api_key": {
      "label": "Secret Key",
      "register": {
        "url": "https://dashboard.stripe.com/apikeys",
        "steps": [
          "Go to Developers > API keys",
          "Copy your Secret key (starts with sk_)"
        ]
      },
      "script": [
        { "type": "copy_key", "note": "Paste your Stripe secret key" }
      ]
    }
  },
  "apis": {
    "rest": {
      "base_url": "https://api.stripe.com/v1",
      "auth_header": "Authorization: Bearer {token}",
      "docs_url": "https://stripe.com/docs/api",
      "spec_url": "https://raw.githubusercontent.com/stripe/openapi/master/openapi/spec3.json",
      "spec_type": "openapi",
      "methods": ["api_key"]
    }
  }
}
```

### GitLab (shared token across APIs)

```json
{
  "schema": "v2",
  "id": "gitlab",
  "label": "GitLab",
  "identity": {
    "label": "Account",
    "hint": "e.g., personal, work"
  },
  "methods": {
    "oauth": {
      "label": "OAuth",
      "endpoints": {
        "authorize": "https://gitlab.com/oauth/authorize",
        "token": "https://gitlab.com/oauth/token"
      },
      "scope": "api read_user",
      "register": {
        "url": "https://gitlab.com/-/profile/applications",
        "steps": [
          "Go to User Settings > Applications",
          "Create a new application",
          "Set redirect URI and scopes",
          "Copy the Application ID and Secret"
        ]
      },
      "script": [
        { "type": "open_url", "value": "{authorize_url}" },
        { "type": "wait_for_callback" }
      ]
    },
    "pat": {
      "label": "Personal Access Token",
      "register": {
        "url": "https://gitlab.com/-/profile/personal_access_tokens",
        "steps": [
          "Go to User Settings > Access Tokens",
          "Create a new token with required scopes",
          "Copy the token"
        ]
      },
      "script": [
        { "type": "copy_key", "note": "Paste your GitLab personal access token" }
      ]
    }
  },
  "apis": {
    "rest": {
      "base_url": "https://gitlab.com/api/v4",
      "auth_header": "PRIVATE-TOKEN: {token}",
      "docs_url": "https://docs.gitlab.com/ee/api/rest/",
      "spec_url": "https://gitlab.com/api/v4/metadata",
      "spec_type": "openapi",
      "methods": ["oauth", "pat"]
    },
    "graphql": {
      "base_url": "https://gitlab.com/api/graphql",
      "auth_header": "Authorization: Bearer {token}",
      "docs_url": "https://docs.gitlab.com/ee/api/graphql/",
      "spec_url": "https://gitlab.com/api/graphql",
      "spec_type": "graphql",
      "methods": ["oauth", "pat"]
    }
  }
}
```
