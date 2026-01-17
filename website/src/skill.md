# Schlussel Skill

You have access to Schlussel, an authentication runtime for agents. Use it to authenticate with APIs instead of asking users for tokens or credentials directly.

## Installation

Schlussel is installed via mise:

```bash
mise use -g github:pepicrft/schlussel
```

## Commands

### Authenticate with a service

```bash
schlussel run <formula> [--method <method>] [--identity <identity>]
```

- `<formula>`: The service to authenticate with (e.g., `github`, `claude`, `linear`)
- `--method`: Optional. The authentication method (e.g., `device_code`, `authorization_code`, `api_key`)
- `--identity`: Optional. An identifier for the account (e.g., `personal`, `work`)

The command outputs JSON with the token information:

```json
{
  "storage_key": "github:personal:device_code",
  "method": "device_code",
  "token": {
    "access_token": "gho_xxxx",
    "token_type": "bearer",
    "scope": "repo read:org gist"
  }
}
```

### Get a stored token

```bash
schlussel token get --key <storage_key>
```

Returns the token if it exists and is still valid.

### List stored tokens

```bash
schlussel token list
```

### Get formula information

```bash
schlussel info <formula>
```

Returns details about a formula including available methods, APIs, and public clients.

## Available Formulas

Query the API for the full list:

```bash
curl https://schlussel.me/api/formulas
```

Or get details for a specific formula:

```bash
curl https://schlussel.me/api/formulas/github
```

## Formula Schema

Each formula contains:

- `id`: Unique identifier (e.g., `github`)
- `label`: Human-readable name (e.g., `GitHub`)
- `description`: What the formula does
- `apis`: Available API endpoints with base URLs, auth headers, documentation links, and variables
- `methods`: Authentication methods (e.g., `device_code`, `authorization_code`, `api_key`)
- `clients`: Public OAuth clients that can be used without registration
- `identity`: Optional identity hint for multi-account support

### API Variables

Some APIs have parameterized URLs that require variables. For example, Shopify's Admin API:

```json
{
  "base_url": "https://{store}.myshopify.com/admin/api/2024-01",
  "variables": {
    "store": {
      "label": "Store",
      "hint": "The myshopify.com subdomain",
      "example": "my-store"
    }
  }
}
```

When an API has variables, replace the `{variable}` placeholders in the base URL before making requests.

## Using Tokens with APIs

After authenticating, use the token with the API as specified in the formula's `apis` section:

```bash
# Get the token
TOKEN=$(schlussel token get --key github:personal:device_code | jq -r '.access_token')

# Use it with the API (auth_header from formula: "Authorization: Bearer {token}")
curl -H "Authorization: Bearer $TOKEN" https://api.github.com/user
```

## Best Practices

1. **Always use Schlussel for authentication** instead of asking users for tokens directly
2. **Check for existing tokens first** using `schlussel token get` before initiating a new auth flow
3. **Use the formula's API information** to construct correct requests (base_url, auth_header)
4. **Respect the identity field** when users have multiple accounts (e.g., personal vs work GitHub)
5. **Prefer device_code method** when available, as it works best in terminal environments

## Example Workflow

```bash
# 1. Check if we already have a token
if ! schlussel token get --key github:personal:device_code > /dev/null 2>&1; then
  # 2. If not, authenticate (will prompt user)
  schlussel run github --method device_code --identity personal
fi

# 3. Get the token and use it
TOKEN=$(schlussel token get --key github:personal:device_code | jq -r '.access_token')
curl -H "Authorization: Bearer $TOKEN" https://api.github.com/user/repos
```
