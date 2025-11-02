#!/bin/bash
set -e

echo "🔨 Building Schlussel XCFramework..."

# Clean previous builds
rm -rf target/xcframework
mkdir -p target/xcframework

# Build for iOS device (ARM64)
echo "📱 Building for iOS (arm64)..."
cargo build --release --target aarch64-apple-ios

# Build for iOS simulator (ARM64 - Apple Silicon Macs)
echo "📱 Building for iOS Simulator (arm64)..."
cargo build --release --target aarch64-apple-ios-sim

# Build for iOS simulator (x86_64 - Intel Macs)
echo "📱 Building for iOS Simulator (x86_64)..."
cargo build --release --target x86_64-apple-ios

# Build for macOS (ARM64 - Apple Silicon)
echo "🖥️  Building for macOS (arm64)..."
cargo build --release --target aarch64-apple-darwin

# Build for macOS (x86_64 - Intel)
echo "🖥️  Building for macOS (x86_64)..."
cargo build --release --target x86_64-apple-darwin

# Create fat library for iOS Simulator (combines x86_64 and arm64)
echo "🔧 Creating fat library for iOS Simulator..."
mkdir -p target/xcframework/ios-simulator
lipo -create \
    target/aarch64-apple-ios-sim/release/libschlussel.a \
    target/x86_64-apple-ios/release/libschlussel.a \
    -output target/xcframework/ios-simulator/libschlussel.a

# Create fat library for macOS (combines x86_64 and arm64)
echo "🔧 Creating fat library for macOS..."
mkdir -p target/xcframework/macos
lipo -create \
    target/aarch64-apple-darwin/release/libschlussel.a \
    target/x86_64-apple-darwin/release/libschlussel.a \
    -output target/xcframework/macos/libschlussel.a

# Copy iOS device library
mkdir -p target/xcframework/ios
cp target/aarch64-apple-ios/release/libschlussel.a target/xcframework/ios/

# Create XCFramework
echo "📦 Creating XCFramework..."
xcodebuild -create-xcframework \
    -library target/xcframework/ios/libschlussel.a \
    -headers include/ \
    -library target/xcframework/ios-simulator/libschlussel.a \
    -headers include/ \
    -library target/xcframework/macos/libschlussel.a \
    -headers include/ \
    -output target/xcframework/Schlussel.xcframework

echo "✅ XCFramework created at target/xcframework/Schlussel.xcframework"
echo ""
echo "📦 To use in Xcode:"
echo "   1. Drag Schlussel.xcframework into your project"
echo "   2. Link with Security.framework (for Keychain access)"
echo "   3. Import: #import <Schlussel/schlussel.h>"
