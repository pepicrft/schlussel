# Formula Schema

Schlussel formulas are JSON documents that describe how an agent can authenticate
against a provider, including supported methods, endpoints, and interaction steps.

## Shape

```json
{
  "id": "provider-id",
  "label": "Provider Name",
  "methods": ["authorization_code", "device_code"],
  "endpoints": {
    "authorize": "https://idp.example.com/oauth/authorize",
    "token": "https://idp.example.com/oauth/token",
    "device": "https://idp.example.com/oauth/device"
  },
  "scope": "space-separated scopes",
  "public_clients": [
    {
      "name": "cli-name",
      "id": "client-id",
      "secret": "optional-client-secret",
      "source": "optional-source-url",
      "methods": ["authorization_code"]
    }
  ],
  "interaction": {
    "register": {
      "url": "https://idp.example.com",
      "steps": ["step one", "step two"]
    },
    "auth_steps": [
      { "type": "open_url", "value": "{authorize_url}" },
      { "type": "wait_for_callback" }
    ]
  },
  "quirks": {
    "dynamic_registration_endpoint": "https://idp.example.com/oauth/register",
    "token_response": "optional-nonstandard-response-key",
    "extra_response_fields": ["extra", "fields"],
    "device_code_poll_endpoint": "/api/auth/device_code/{device_code}",
    "device_code_browser_url": "/auth/device_codes/{device_code}"
  }
}
```

## Field Notes

- `id` and `label` are required.
- `methods` is required; valid values are `authorization_code` and `device_code`.
- `endpoints.authorize` and `endpoints.token` are required.
- `endpoints.device` is optional and only needed for `device_code`.
- `scope` is optional and space-separated.
- `public_clients` is optional. Each entry can optionally include `methods` to scope the client to specific methods.
- `interaction` is optional. `register.url` and `register.steps` are required when present.
- `interaction.auth_steps` is optional. Each entry must include `type` and can include `value` and `note`.
- `quirks` is optional; all fields inside are optional.

## Interaction Steps

Interaction steps describe the user-visible actions an agent should display.
Common `type` values include `open_url`, `enter_code`, `wait_for_callback`,
and `wait_for_token`.

Values can include placeholders resolved at runtime:

- `{authorize_url}`
- `{verification_uri}`
- `{verification_uri_complete}`
- `{user_code}`
- `{device_code}`
