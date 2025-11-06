#!/bin/bash
set -e

VERSION=${1:-"0.1.5"}

echo "📦 Building Schlussel Artifact Bundle v${VERSION}..."
echo ""

# Clean previous builds
rm -rf target/artifactbundle
mkdir -p target/artifactbundle

# Create artifact bundle structure
BUNDLE_DIR="target/artifactbundle/Schlussel.artifactbundle"
VERSION_DIR="${BUNDLE_DIR}/schlussel-${VERSION}"

mkdir -p "${VERSION_DIR}/lib"
mkdir -p "${VERSION_DIR}/include"

# Copy headers
echo "📄 Copying headers..."
cp -r include/* "${VERSION_DIR}/include/"

# Build for each platform
echo ""
echo "🔨 Building for multiple platforms..."
echo ""

# macOS (universal binary)
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "🍎 Building for macOS..."

    # Check if targets are installed
    for target in aarch64-apple-darwin x86_64-apple-darwin; do
        if ! rustup target list | grep -q "$target (installed)"; then
            echo "   Installing $target..."
            rustup target add $target
        fi
    done

    cargo build --release --target aarch64-apple-darwin
    cargo build --release --target x86_64-apple-darwin

    # Create universal binary
    lipo -create \
        target/aarch64-apple-darwin/release/libschlussel.a \
        target/x86_64-apple-darwin/release/libschlussel.a \
        -output "${VERSION_DIR}/lib/libschlussel-macos.a"

    echo "   ✅ macOS universal binary created"
fi

# Linux x86_64 (using Docker/Podman - native build in x86_64 container)
echo ""
echo "🐧 Building for Linux x86_64..."

# Detect container runtime
if command -v docker &> /dev/null; then
    CONTAINER_CMD="docker"
elif command -v podman &> /dev/null; then
    CONTAINER_CMD="podman"
else
    echo "   ⚠️  No container runtime found (docker/podman), skipping Linux builds"
    CONTAINER_CMD=""
fi

if [ -n "$CONTAINER_CMD" ]; then
    echo "   Using $CONTAINER_CMD for Linux builds..."

    # Build x86_64
    $CONTAINER_CMD run --rm \
        -v "$(pwd)":/workspace \
        -w /workspace \
        --platform linux/amd64 \
        rust:latest \
        bash -c "apt-get update -qq && apt-get install -y -qq libssl-dev pkg-config > /dev/null 2>&1 && cargo build --release 2>&1" || {
            echo "   ⚠️  Linux x86_64 build failed (may be emulation issue on ARM64 host)"
            echo "   💡  Linux builds will be handled by CI on native Linux runners"
        }

    if [ -f target/release/libschlussel.a ]; then
        cp target/release/libschlussel.a "${VERSION_DIR}/lib/libschlussel-linux-x86_64.a"
        echo "   ✅ Linux x86_64 binary created"
        rm -rf target/release
    fi

    # Build ARM64
    echo ""
    echo "🐧 Building for Linux ARM64..."
    $CONTAINER_CMD run --rm \
        -v "$(pwd)":/workspace \
        -w /workspace \
        --platform linux/arm64 \
        rust:latest \
        bash -c "apt-get update -qq && apt-get install -y -qq libssl-dev pkg-config > /dev/null 2>&1 && cargo build --release 2>&1" || {
            echo "   ⚠️  Linux ARM64 build failed"
        }

    if [ -f target/release/libschlussel.a ]; then
        cp target/release/libschlussel.a "${VERSION_DIR}/lib/libschlussel-linux-aarch64.a"
        echo "   ✅ Linux ARM64 binary created"
    fi

    # Windows x86_64 (cross-compile using mingw)
    echo ""
    echo "🪟 Building for Windows x86_64..."
    $CONTAINER_CMD run --rm \
        -v "$(pwd)":/workspace \
        -w /workspace \
        rust:latest \
        bash -c "rustup target add x86_64-pc-windows-gnu && apt-get update -qq && apt-get install -y -qq mingw-w64 pkg-config libssl-dev > /dev/null 2>&1 && cargo build --release --target x86_64-pc-windows-gnu 2>&1" || {
            echo "   ⚠️  Windows x86_64 build failed"
        }

    if [ -f target/x86_64-pc-windows-gnu/release/schlussel.lib ] || [ -f target/x86_64-pc-windows-gnu/release/libschlussel.a ]; then
        # Copy .a file and rename to .lib for Windows
        if [ -f target/x86_64-pc-windows-gnu/release/libschlussel.a ]; then
            cp target/x86_64-pc-windows-gnu/release/libschlussel.a "${VERSION_DIR}/lib/schlussel-windows-x86_64.lib"
        else
            cp target/x86_64-pc-windows-gnu/release/schlussel.lib "${VERSION_DIR}/lib/schlussel-windows-x86_64.lib"
        fi
        echo "   ✅ Windows x86_64 binary created"
    fi
fi

# Create info.json dynamically based on which binaries exist
echo ""
echo "📝 Creating artifact bundle metadata..."

# Build variants array based on existing files
VARIANTS=""
FIRST=true

if [ -f "${VERSION_DIR}/lib/libschlussel-macos.a" ]; then
    VARIANTS="${VARIANTS}        {
          \"path\": \"schlussel-${VERSION}/lib/libschlussel-macos.a\",
          \"supportedTriples\": [\"x86_64-apple-macosx\", \"arm64-apple-macosx\"],
          \"staticLibraryMetadata\": {
            \"headerPaths\": [\"schlussel-${VERSION}/include\"],
            \"moduleMapPath\": \"schlussel-${VERSION}/include/module.modulemap\"
          }
        }"
    FIRST=false
fi

if [ -f "${VERSION_DIR}/lib/libschlussel-linux-x86_64.a" ]; then
    [ "$FIRST" = false ] && VARIANTS="${VARIANTS},"
    VARIANTS="${VARIANTS}
        {
          \"path\": \"schlussel-${VERSION}/lib/libschlussel-linux-x86_64.a\",
          \"supportedTriples\": [\"x86_64-unknown-linux-gnu\"],
          \"staticLibraryMetadata\": {
            \"headerPaths\": [\"schlussel-${VERSION}/include\"],
            \"moduleMapPath\": \"schlussel-${VERSION}/include/module.modulemap\"
          }
        }"
    FIRST=false
fi

if [ -f "${VERSION_DIR}/lib/libschlussel-linux-aarch64.a" ]; then
    [ "$FIRST" = false ] && VARIANTS="${VARIANTS},"
    VARIANTS="${VARIANTS}
        {
          \"path\": \"schlussel-${VERSION}/lib/libschlussel-linux-aarch64.a\",
          \"supportedTriples\": [\"aarch64-unknown-linux-gnu\"],
          \"staticLibraryMetadata\": {
            \"headerPaths\": [\"schlussel-${VERSION}/include\"],
            \"moduleMapPath\": \"schlussel-${VERSION}/include/module.modulemap\"
          }
        }"
    FIRST=false
fi

if [ -f "${VERSION_DIR}/lib/schlussel-windows-x86_64.lib" ]; then
    [ "$FIRST" = false ] && VARIANTS="${VARIANTS},"
    VARIANTS="${VARIANTS}
        {
          \"path\": \"schlussel-${VERSION}/lib/schlussel-windows-x86_64.lib\",
          \"supportedTriples\": [\"x86_64-unknown-windows-msvc\"],
          \"staticLibraryMetadata\": {
            \"headerPaths\": [\"schlussel-${VERSION}/include\"],
            \"moduleMapPath\": \"schlussel-${VERSION}/include/module.modulemap\"
          }
        }"
    FIRST=false
fi

cat > "${BUNDLE_DIR}/info.json" << EOF
{
  "schemaVersion": "1.0",
  "artifacts": {
    "schlussel": {
      "version": "${VERSION}",
      "type": "staticLibrary",
      "variants": [
${VARIANTS}
      ]
    }
  }
}
EOF

# Create archive
echo ""
echo "📦 Creating artifact bundle archive..."
cd target/artifactbundle
zip -r "../Schlussel.artifactbundle.zip" "Schlussel.artifactbundle"
cd ../..

# Calculate checksum for SwiftPM
echo ""
echo "🔐 Calculating checksum..."
if command -v swift &> /dev/null; then
    CHECKSUM=$(swift package compute-checksum target/Schlussel.artifactbundle.zip)
    echo "   Checksum: ${CHECKSUM}"
    echo "${CHECKSUM}" > target/Schlussel.artifactbundle.checksum
else
    echo "   ⚠️  Swift not found, skipping checksum calculation"
fi

echo ""
echo "✅ Artifact bundle created!"
echo ""
echo "📦 Location: target/Schlussel.artifactbundle.zip"
echo ""
echo "📁 Contents:"
ls -lh "${VERSION_DIR}/lib/" | tail -n +2

echo ""
echo "📋 To use in Package.swift:"
echo ""
echo ".binaryTarget("
echo "    name: \"Schlussel\","
echo "    url: \"https://github.com/tuist/schlussel/releases/download/v${VERSION}/Schlussel.artifactbundle.zip\","
if [ -f target/Schlussel.artifactbundle.checksum ]; then
    echo "    checksum: \"$(cat target/Schlussel.artifactbundle.checksum)\""
fi
echo ")"
