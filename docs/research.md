# OAuth API Research

This document catalogs APIs that support device code flow, public OAuth clients, or other authentication methods suitable for CLI tools.

## Completed Formulas

| API | Auth Methods | Status | Notes |
|-----|--------------|--------|-------|
| Reddit | Device Code, Installed App | ✅ Done | Installed app flow with public client |
| Hugging Face | Device Code, Token | ✅ Done | Native device code support |
| Notion | OAuth | ✅ Done | Public mobile/desktop clients |
| Slack | OAuth | ✅ Done | Bot token authentication |
| Dropbox | Device Code | ✅ Done | Already in repo |
| Google | Device Code | ✅ Done | Already in repo |
| Spotify | Device Code | ✅ Done | Already in repo |
| Twitch | Device Code | ✅ Done | Already in repo |
| Zoom | Device Code | ✅ Done | Already in repo |

## APIs with Device Code Flow

### Confirmed Support

1. **Google** - `https://oauth-redirect.googleusercontent.com/o/device` (already formula)
2. **Microsoft/Azure** - `https://login.microsoftonline.com/common/oauth2/devicecode` (already formula)
3. **Spotify** - `https://accounts.spotify.com/oauth/authorize` with device code extension (already formula)
4. **Twitch** - `https://id.twitch.tv/oauth2/device` (already formula)
5. **Dropbox** - `https://www.dropbox.com/oauth2/authorize` with device code (already formula)
6. **Zoom** - `https://zoom.us/oauth/authorize` with device code (already formula)
7. **Reddit** - `https://www.reddit.com/api/v1/device_authorization` ✅ Added
8. **Hugging Face** - `https://huggingface.com/oauth/device/authorization` ✅ Added

### Likely Support

These APIs likely support device code flow but need verification:

- **GitHub** - Check `device_flow` parameter on OAuth endpoints
- **GitLab** - Check device flow support in OAuth docs
- **Discord** - Check OAuth2 device grant
- **Discord Developer Portal** - May have device code

## Public Client APIs

APIs with known public client applications that expose client_id and redirect_uris:

### Mobile/Desktop Public Clients

1. **Notion** - Mobile and desktop apps have known public clients ✅ Added
2. **Slack** - CLI and desktop apps have public clients ✅ Added
3. **Linear** - Desktop app (already formula)
4. **Shopify** - Mobile app public clients (already formula)
5. **Vercel** - CLI public client (already formula)

### To Investigate

- **Figma** - Desktop app likely has public OAuth
- **Loom** - Desktop app OAuth clients
- **Raycast** - Extension OAuth flows
- **Fig** - CLI OAuth flows

## OAuth without Confidential Secrets

### Public Client / PKCE Only

These APIs support public clients or PKCE without client secrets:

1. **Linear** - MCP OAuth with `token_endpoint_auth_method: none` (already formula)
2. **Stripe** - MCP OAuth (already formula)
3. **Reddit** - Installed app flow (no secret) ✅ Added
4. **Hugging Face** - Device code with no secret ✅ Added

### Token-Based (API Keys)

APIs that support simple token-based authentication:

1. **Hugging Face** - Access tokens ✅ Added
2. **Linear** - Personal API keys (already formula)
3. **Stripe** - API keys (already formula)
4. **OpenAI** - API keys (need formula)
5. **Anthropic** - API keys (need formula)

## API Discovery Sources

### Documentation Pages
- RFC 8628: OAuth 2.0 Device Authorization Grant
- Each provider's developer documentation

### Code References
- GitHub repos of official CLI tools
- Mobile app decompilation for client IDs
- Open source OAuth client libraries

### Community Resources
- OAuth 2.0 Providers list on Wikipedia
- OAuth toolkits and SDKs

## Priority Additions

### High Priority (Device Code Confirmed)
- [ ] **OpenAI** - Check device code support
- [ ] **Anthropic** - Check device code support
- [ ] **AWS/Cognito** - Check device code flow

### Medium Priority (Likely Device Code)
- [ ] **GitHub** - Verify device flow
- [ ] **GitLab** - Verify device flow
- [ ] **Discord** - Verify device flow

### Low Priority (Need Research)
- [ ] **Figma** - Desktop app client
- [ ] **Loom** - OAuth client
- [ ] **Calendly** - OAuth with public client
- [ ] **Airtable** - OAuth with public client

## Notes

- Client secrets in this repo are for demonstration - users should register their own
- Some public clients may have rate limits or restrictions
- Always verify current OAuth configuration with provider docs
