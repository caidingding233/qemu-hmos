#!/bin/bash
set -euo pipefail

echo "=== Local QEMU Build Test ==="
echo "This script tests QEMU build without requiring HarmonyOS SDK"
echo ""

# Check if we're in the right directory
if [ ! -d "third_party/qemu" ]; then
    echo "❌ Error: Please run this script from the project root"
    exit 1
fi

echo "=== Environment Check ==="
echo "Current directory: $(pwd)"
echo "QEMU directory exists: $([ -d "third_party/qemu" ] && echo "Yes" || echo "No")"
echo ""

# Check for system dependencies
echo "=== Checking System Dependencies ==="
MISSING_DEPS=()

if ! command -v gcc &> /dev/null; then
    MISSING_DEPS+=("gcc")
fi

if ! command -v g++ &> /dev/null; then
    MISSING_DEPS+=("g++")
fi

if ! command -v make &> /dev/null; then
    MISSING_DEPS+=("make")
fi

if ! command -v pkg-config &> /dev/null; then
    MISSING_DEPS+=("pkg-config")
fi

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo "❌ Missing dependencies: ${MISSING_DEPS[*]}"
    echo "Please install them first:"
    echo "  macOS: brew install ${MISSING_DEPS[*]}"
    echo "  Ubuntu: sudo apt-get install ${MISSING_DEPS[*]}"
    exit 1
fi

echo "✅ All system dependencies found"
echo ""

# Check for optional dependencies
echo "=== Checking Optional Dependencies ==="
OPTIONAL_DEPS=("glib-2.0" "pixman-1" "openssl")

for dep in "${OPTIONAL_DEPS[@]}"; do
    if pkg-config --exists "$dep" 2>/dev/null; then
        echo "✅ $dep: $(pkg-config --modversion "$dep")"
    else
        echo "⚠️  $dep: not found (will be disabled)"
    fi
done
echo ""

# Prepare QEMU build
echo "=== Preparing QEMU Build ==="
cd third_party/qemu

# Clean previous builds
echo "Cleaning previous builds..."
rm -rf build_local_test
mkdir -p build_local_test
cd build_local_test

# Configure QEMU for local testing
echo "Configuring QEMU for local testing..."
../configure \
  --target-list=aarch64-softmmu \
  --enable-tcg \
  --disable-kvm \
  --disable-xen \
  --disable-werror \
  --disable-vnc \
  --disable-vhost-user \
  --disable-vhost-user-blk-server \
  --disable-libvduse \
  --disable-vduse-blk-export \
  --disable-vhost-net \
  --disable-vhost-kernel \
  --disable-keyring \
  --disable-guest-agent \
  --disable-slirp \
  --disable-curl \
  --disable-fdt \
  --static

# Build QEMU
echo "Building QEMU..."
make -j$(nproc)

# Verify build results
echo "=== Build Verification ==="
if [ ! -f "libqemu-aarch64-softmmu.a" ]; then
    echo "❌ Error: libqemu-aarch64-softmmu.a not found"
    exit 1
fi

if [ ! -f "libqemuutil.a" ]; then
    echo "❌ Error: libqemuutil.a not found"
    exit 1
fi

echo "✅ QEMU build successful"
echo ""

# Show build results
echo "=== Build Results ==="
echo "Generated libraries:"
ls -la *.a
echo ""
echo "Library sizes:"
du -h *.a
echo ""

# Test if we can create a simple shared library
echo "=== Testing Shared Library Creation ==="
if command -v g++ &> /dev/null; then
    echo "Creating test shared library..."
    g++ -shared -fPIC -Wl,--no-undefined \
      -Wl,--whole-archive \
      libqemu-aarch64-softmmu.a \
      libqemuutil.a \
      -Wl,--no-whole-archive \
      -lpthread -ldl -lm -lz \
      -o libqemu_test.so
    
    if [ -f "libqemu_test.so" ]; then
        echo "✅ Test shared library created successfully"
        echo "Size: $(du -h libqemu_test.so | cut -f1)"
        echo "Type: $(file libqemu_test.so)"
    else
        echo "❌ Failed to create test shared library"
    fi
else
    echo "⚠️  g++ not available, skipping shared library test"
fi

echo ""
echo "🎉 Local build test completed!"
echo ""
echo "Next steps:"
echo "1. If this build succeeded, the issue is with HarmonyOS SDK setup"
echo "2. Run scripts/debug-sdk-paths.sh to check SDK installation"
echo "3. Make sure HarmonyOS SDK is properly installed and configured"
