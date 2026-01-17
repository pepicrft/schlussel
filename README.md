# 🔑 Schlussel

**Authentication runtime for agents and CLI applications**

Authenticate with APIs without copying tokens or managing credentials manually. Schlussel handles OAuth flows, token storage, and automatic refresh so you can focus on building.

## ✨ Features

- 🔐 **Multiple OAuth methods** - Device code flow, authorization code with PKCE
- 🔄 **Automatic refresh** - OAuth2 tokens are refreshed automatically when expired
- 🔒 **Cross-process safe** - Multiple processes can safely access and refresh tokens
- 🌍 **Cross-platform** - Linux, macOS, Windows on x86_64 and ARM64

## 📦 Installation

Install via [mise](https://mise.jdx.dev/):

```bash
mise use -g github:pepicrft/schlussel
```

## 🚀 Usage

### Authenticate with a service

```bash
schlussel run github --method device_code --identity personal
```

This opens a browser, handles the OAuth flow, and stores the token securely in your OS credential manager.

### Use the token

```bash
TOKEN=$(schlussel token get --formula github --method device_code --identity personal)
curl -H "Authorization: Bearer $TOKEN" https://api.github.com/user
```

### Manage tokens

```bash
# List all stored tokens
schlussel token list

# List tokens for a specific service
schlussel token list --formula github

# Delete a token
schlussel token delete --formula github --method device_code --identity personal
```

## 🔌 Available Services

Query the API for available formulas:

```bash
curl https://schlussel.me/api/formulas
```

Or get details for a specific service:

```bash
curl https://schlussel.me/api/formulas/github
```

## 📚 Documentation

Full documentation available at [schlussel.me/docs](https://schlussel.me/docs)

## 🤝 Contributing

Contributions welcome! Please ensure tests pass and code is formatted:

```bash
zig build test
zig fmt --check src/
```

## 📄 License

See [LICENSE](LICENSE) for details.
