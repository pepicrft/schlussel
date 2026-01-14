# Formula Schema

Schlussel formulas are JSON documents that describe an OAuth 2.0 provider for the library and CLI.

## Shape

```json
{
  "id": "provider-id",
  "label": "Provider Name",
  "flows": ["authorization_code", "device_code"],
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
      "flows": ["authorization_code"]
    }
  ],
  "onboarding": {
    "register_url": "https://idp.example.com",
    "steps": ["step one", "step two"]
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
- `flows` is required; valid values are `authorization_code` and `device_code`.
- `endpoints.authorize` and `endpoints.token` are required.
- `endpoints.device` is optional and only needed for `device_code`.
- `scope` is optional and space-separated.
- `public_clients` is optional. Each entry can optionally include `flows` to scope the client to specific flows.
- `onboarding` is optional; `register_url` and `steps` are required when present.
- `quirks` is optional; all fields inside are optional.
