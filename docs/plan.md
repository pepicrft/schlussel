# Scripts

Scripts are structured instructions that tell an agent how to guide
the user through authentication. They are emitted by `schlussel script` and can
be executed once resolved by `schlussel run`.

## Script Output

`schlussel script <provider>` emits:

- `methods`: supported authentication methods.
- `script`: declarative steps from the formula.
- `storage`: storage hints for naming and labeling saved credentials.
- `method` and `context` (optional): resolved values when `--resolve` is set.

## Step Types

Common step types:

- `open_url`: prompt the user to open a URL.
- `enter_code`: prompt the user to enter a code.
- `copy_key`: prompt the user to provide an API key or token.
- `wait_for_callback`: wait for an OAuth callback.
- `wait_for_token`: poll for token completion.

## Placeholders

Steps can reference placeholders that are resolved at runtime:

- `{authorize_url}`
- `{verification_uri}`
- `{verification_uri_complete}`
- `{user_code}`
- `{device_code}`

## Resolved Context

When `--resolve` is used, the script includes a `context` object with values
needed to complete the flow:

- `authorize_url`, `pkce_verifier`, `state`, `redirect_uri`
- `device_code`, `user_code`, `verification_uri`, `verification_uri_complete`
- `interval`, `expires_in`

## CLI Usage

```bash
# Emit a script
schlussel script github

# Print the formula schema
schlussel script --json-schema

# Emit a resolved script
schlussel script github --method device_code --resolve > script.json

# Execute a resolved script
schlussel run github --script-json script.json

# Execute a resolved script from stdin
cat script.json | schlussel run --script-json -

# Execute from stdin without flags
cat script.json | schlussel run -

# Resolve and run directly (no script file)
schlussel run github --method device_code

# Emit machine-readable output
schlussel run github --script-json script.json --json
```

## Non-OAuth Methods

When the script method is `api_key` or `personal_access_token`, `schlussel run`
prints the script steps and stores the provided secret as a token:

- pass `--credential` to provide the secret non-interactively
- otherwise, the CLI prompts for the secret on stdin

Storage keys follow the formula `storage.key_template` when present, otherwise
`{formula_id}:{method}`.

If the template includes `{identity}`, pass `--identity` when running the script
so multiple identities can be stored side-by-side.
