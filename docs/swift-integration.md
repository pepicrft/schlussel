# 📱 Swift Integration

Using Schlussel from Swift via XCFramework (Apple platforms) or Artifact Bundle (cross-platform).

---

## 🚀 Quick Start

### Option 1: Swift Package Manager (Recommended - Cross-Platform)

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/tuist/schlussel", from: "0.2.2")
]
```

Or use the artifact bundle directly:

```swift
.binaryTarget(
    name: "Schlussel",
    url: "https://github.com/tuist/schlussel/releases/download/0.2.2/Schlussel.artifactbundle.zip",
    checksum: "f85b56fe4daabce63b811bfc50c99f12ae87cb6df7cb57e784eb097c38839780"
)
```

**Supports:**
- ✅ macOS (x86_64, ARM64)
- ✅ Linux (x86_64, ARM64) 
- ⚠️ Windows (planned)

### Option 2: XCFramework (Apple Platforms Only)

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

## 📦 Distribution Options

### Artifact Bundle (Cross-Platform)

**Best for:** CLI tools, server-side Swift, cross-platform apps

The artifact bundle includes pre-compiled static libraries for multiple platforms:

```swift
.binaryTarget(
    name: "Schlussel",
    url: "https://github.com/tuist/schlussel/releases/download/0.2.2/Schlussel.artifactbundle.zip",
    checksum: "f85b56fe4daabce63b811bfc50c99f12ae87cb6df7cb57e784eb097c38839780"
)
```

**Platforms:**
- ✅ macOS (x86_64 + ARM64 universal)
- ✅ Linux x86_64
- ✅ Linux ARM64

**Tested on:**
- macOS 13+ with Swift 5.9+
- Ubuntu 22.04+ with Swift 5.9+
- Debian-based Linux distributions

### XCFramework (Apple Only)

**Best for:** iOS apps, macOS apps with iOS target

Download from [releases](https://github.com/tuist/schlussel/releases/latest) or build locally:

```bash
./scripts/build-xcframework.sh
```

**Platforms:**
- ✅ iOS devices (ARM64)
- ✅ iOS Simulator (x86_64 + ARM64)
- ✅ macOS (x86_64 + ARM64)

---

## 🛠️ Platform Support Summary

| Platform | Artifact Bundle | XCFramework |
|----------|----------------|-------------|
| macOS | ✅ | ✅ |
| Linux | ✅ | ❌ |
| Windows | 🔜 | ❌ |
| iOS | ❌ | ✅ |
| iOS Simulator | ❌ | ✅ |

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
