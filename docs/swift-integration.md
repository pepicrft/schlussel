# 📱 Swift/iOS Integration

Using Schlussel from Swift via XCFramework.

---

## 🚀 Quick Start

### 1. Build XCFramework

```bash
./scripts/build-xcframework.sh
```

This creates `target/xcframework/Schlussel.xcframework` with support for:
- iOS devices (ARM64)
- iOS Simulator (x86_64 + ARM64)
- macOS (x86_64 + ARM64)

### 2. Add to Your Xcode Project

1. Drag `Schlussel.xcframework` into your Xcode project
2. Link with `Security.framework` (for Keychain access)
3. Import the Swift wrapper: Add `Schlussel.swift` to your project

### 3. Use in Swift

```swift
import Foundation

// Create OAuth client for GitHub
guard let client = SchlusselClient(
    githubClientId: "your-client-id",
    scopes: "repo user",
    appName: "my-app"
) else {
    print("❌ Failed to create client")
    return
}

// Authorize using Device Code Flow
guard let token = client.authorizeDevice() else {
    print("❌ Authorization failed")
    return
}

// Save token securely (in Keychain)
_ = client.saveToken(key: "github.com:user", token: token)

// Use token
if let accessToken = token.accessToken {
    print("✅ Access token: \\(accessToken)")
    
    // Make API requests...
}
```

---

## 🔐 Security

**Tokens are stored in macOS Keychain automatically!**

- ✅ Encrypted by the system
- ✅ Protected by macOS security
- ✅ Accessible only to your app
- ✅ Survives app restarts

---

## 📦 Distribution

### Option 1: Include XCFramework Directly

Bundle `Schlussel.xcframework` with your app.

### Option 2: Swift Package Manager (Future)

Once published, add to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/tuist/schlussel", from: "0.1.0")
]
```

---

## 🛠️ Platform Support

| Platform | Supported | Architecture |
|----------|-----------|--------------|
| iOS | ✅ | ARM64 |
| iOS Simulator | ✅ | x86_64, ARM64 |
| macOS | ✅ | x86_64, ARM64 |
| macCatalyst | 🔜 | Coming soon |
| tvOS | 🔜 | Coming soon |
| watchOS | 🔜 | Coming soon |

---

## 📝 API Reference

### SchlusselClient

```swift
init?(githubClientId: String, scopes: String?, appName: String)
func authorizeDevice() -> SchlusselToken?
func saveToken(key: String, token: SchlusselToken) -> Bool
```

### SchlusselToken

```swift
var accessToken: String? { get }
var isExpired: Bool { get }
```

---

## 🔧 Build Requirements

To build the XCFramework yourself:

- Rust toolchain with iOS targets
- Xcode Command Line Tools
- macOS (for `xcodebuild` and `lipo`)

### Install Rust Targets

```bash
rustup target add aarch64-apple-ios
rustup target add aarch64-apple-ios-sim
rustup target add x86_64-apple-ios
rustup target add aarch64-apple-darwin
rustup target add x86_64-apple-darwin
```

---

## 💡 Example App

See [examples/swift-example/](../examples/swift-example/) for a complete iOS app example.

---

**Back to:** [Documentation Index](README.md)
