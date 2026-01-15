# Formula Schema

Schlussel formulas are JSON documents that describe how an agent can authenticate
against a provider, including supported methods, endpoints, and script steps.

## Shape

```json
{
  "schema": "v1",
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
  "script": {
    "register": {
      "url": "https://idp.example.com",
      "steps": ["step one", "step two"]
    },
    "steps": [
      { "type": "open_url", "value": "{authorize_url}" },
      { "type": "wait_for_callback" }
    ]
  },
  "storage": {
    "key_template": "{formula_id}:{method}",
    "label": "Provider Name",
    "value_label": "Access token",
    "identity_label": "Workspace",
    "identity_hint": "Use the org slug",
    "rotation_url": "https://idp.example.com/settings/tokens",
    "rotation_hint": "Rotate every 90 days"
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

- `schema` is required. Current version is `v1`.
- `id` and `label` are required.
- `methods` is required; valid values are `authorization_code`, `device_code`, `api_key`, `personal_access_token`.
- `endpoints.authorize` and `endpoints.token` are required when using OAuth methods.
- `endpoints.device` is optional and only needed for `device_code`.
- `scope` is optional and space-separated.
- `public_clients` is optional. Each entry can optionally include `methods` to scope the client to specific methods.
- `script` is optional. `register.url` and `register.steps` are required when present.
- `script.steps` is optional. Each entry must include `type` and can include `value` and `note`.
- `storage` is optional. Use it to tell agents how to store and label the secret.
- `storage.key_template` controls the storage key. Default is `{formula_id}:{method}`.
- `storage.label` and `storage.value_label` are UI hints for agent prompts.
- `storage.identity_label` and `storage.identity_hint` describe how to name distinct identities.
- `storage.rotation_url` and `storage.rotation_hint` describe rotation rules.
- `quirks` is optional; all fields inside are optional.

## Non-OAuth Methods

Formulas can model API key or personal access token flows without OAuth
endpoints:

```json
{
  "schema": "v1",
  "id": "acme-api",
  "label": "Acme API",
  "methods": ["api_key"],
  "script": {
    "register": {
      "url": "https://acme.example.com/settings/api",
      "steps": [
        "Open your Acme settings",
        "Create a new API key"
      ]
    },
    "steps": [
      { "type": "copy_key", "note": "Paste your API key into the agent." }
    ]
  }
}
```

For non-OAuth methods, `schlussel run` stores the provided secret as a token.
Agents can also use the script steps and collect the secret themselves.

Storage keys should use the template rules defined in `storage.key_template`.
The default template is `{formula_id}:{method}` and supports:

- `{formula_id}`: the formula `id`
- `{method}`: the selected authentication method
- `{identity}`: a user-provided identifier (for multiple identities)

## Script Steps

Script steps describe the user-visible actions an agent should display.
Common `type` values include `open_url`, `enter_code`, `wait_for_callback`,
and `wait_for_token`.

Values can include placeholders resolved at runtime:

- `{authorize_url}`
- `{verification_uri}`
- `{verification_uri_complete}`
- `{user_code}`
- `{device_code}`
