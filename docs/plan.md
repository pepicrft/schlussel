# Interaction Plans

Interaction plans are structured instructions that tell an agent how to guide
the user through authentication. They are emitted by `schlussel plan` and can
be executed by `schlussel run`.

## Plan Output

`schlussel plan <provider>` emits:

- `methods`: supported authentication methods.
- `interaction`: declarative steps from the formula.
- `plan` (optional): resolved steps and context when `--resolve` is set.

## Step Types

Common step types:

- `open_url`: prompt the user to open a URL.
- `enter_code`: prompt the user to enter a code.
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

When `--resolve` is used, the plan includes a `context` object with values
needed to complete the flow:

- `authorize_url`, `pkce_verifier`, `state`, `redirect_uri`
- `device_code`, `user_code`, `verification_uri`, `verification_uri_complete`
- `interval`, `expires_in`

## CLI Usage

```bash
# Emit a plan
schlussel plan github

# Emit a resolved plan
schlussel plan github --method device_code --resolve > plan.json

# Execute a resolved plan
schlussel run github --plan-json plan.json

# Execute a resolved plan from stdin
cat plan.json | schlussel run github --plan-json -
```
