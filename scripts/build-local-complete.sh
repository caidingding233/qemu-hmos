#!/bin/bash

# Complete local build script for QEMU on HarmonyOS
# This script downloads SDK and builds everything locally

set -e

echo "=== Complete Local Build for QEMU on HarmonyOS ==="

# Check if we're on macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
  echo "⚠️  Warning: You're on macOS. This script is designed for Linux."
  echo "The build will likely fail due to missing dependencies."
  echo "Consider using GitHub Actions for cloud building instead."
  echo ""
  read -p "Do you want to continue anyway? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Build cancelled."
    exit 1
  fi
fi

# Install dependencies (skip on macOS)
if [[ "$OSTYPE" != "darwin"* ]]; then
  echo "=== Installing dependencies ==="
  sudo apt-get update
  sudo apt-get install -y build-essential cmake curl wget unzip python3 \
                        libglib2.0-dev libpixman-1-dev libssl-dev \
                        libcurl4-openssl-dev libssh-dev libgnutls28-dev \
                        libsasl2-dev libpam0g-dev libbz2-dev libzstd-dev \
                        libpcre2-dev pkg-config meson tree
else
  echo "=== Skipping dependency installation on macOS ==="
  echo "Make sure you have the required tools installed via Homebrew:"
  echo "brew install cmake curl wget python3 glib pixman openssl pcre2 pkg-config meson tree"
fi

# Download and setup SDK
echo "=== Downloading SDK ==="
if [ -f "ohos-sdk-windows_linux-public.tar.gz" ]; then
  echo "SDK already downloaded, skipping..."
else
  curl -OL https://repo.huaweicloud.com/openharmony/os/5.1.0-Release/ohos-sdk-windows_linux-public.tar.gz
fi

echo "=== Extracting SDK ==="
tar -xzf ohos-sdk-windows_linux-public.tar.gz
rm ohos-sdk-windows_linux-public.tar.gz
rm -rf ohos-sdk/{ohos,windows}

echo "=== Processing SDK ==="
cd ohos-sdk/linux

echo "=== Current directory ==="
pwd
ls -la

echo "=== Finding native SDK zip ==="
NATIVE_ZIP=$(find . -name "native-linux-x64-*.zip" | head -1)
if [ -z "$NATIVE_ZIP" ]; then
  echo "❌ Could not find native-linux-x64-*.zip"
  echo "Available files:"
  ls -la
  echo ""
  echo "All zip files:"
  find . -name "*.zip" -type f
  exit 1
fi

echo "✅ Found native SDK: $NATIVE_ZIP"

echo "=== Extracting native SDK ==="
unzip -q "$NATIVE_ZIP"
rm "$NATIVE_ZIP"

echo "=== Verifying extraction ==="
echo "Contents after extraction:"
ls -la

# Look for the extracted directory
echo "=== Looking for native directory ==="
NATIVE_DIR=$(find . -name "native-linux-x64-*" -type d | head -1)
echo "Search result: '$NATIVE_DIR'"

if [ -z "$NATIVE_DIR" ]; then
  echo "❌ Could not find native-linux-x64-* directory"
  echo "Available directories:"
  find . -type d
  echo ""
  echo "All files:"
  find . -type f | head -20
  exit 1
fi

echo "✅ Found native directory: $NATIVE_DIR"

echo "=== Analyzing native directory ==="
echo "Contents of $NATIVE_DIR:"
ls -la "$NATIVE_DIR"

echo ""
echo "=== Setting up environment ==="
# Set up paths based on the correct structure
export OHOS_NDK_HOME="$(pwd)/$NATIVE_DIR"
export SYSROOT="$(pwd)/$NATIVE_DIR/sysroot"
export CC="$(pwd)/$NATIVE_DIR/llvm/bin/aarch64-unknown-linux-ohos-clang"
export CXX="$(pwd)/$NATIVE_DIR/llvm/bin/aarch64-unknown-linux-ohos-clang++"
export CMAKE="$(pwd)/$NATIVE_DIR/build-tools/cmake/bin/cmake"

echo "=== Verifying tools ==="
echo "OHOS_NDK_HOME: $OHOS_NDK_HOME"
echo "SYSROOT: $SYSROOT"
echo "CC: $CC"
echo "CXX: $CXX"
echo "CMAKE: $CMAKE"

echo ""
echo "=== Testing compiler ==="
if [ -f "$CC" ]; then
  echo "✅ CC exists: $CC"
  file "$CC"
  "$CC" --version 2>&1 | head -3 || echo "Version check failed"
else
  echo "❌ CC not found: $CC"
  echo "Available files in llvm/bin:"
  if [ -d "$(dirname "$CC")" ]; then
    ls -la "$(dirname "$CC")" || echo "Cannot list llvm/bin"
  else
    echo "llvm/bin directory does not exist"
  fi
  
  echo ""
  echo "Looking for any clang files:"
  find "$NATIVE_DIR" -name "*clang*" -type f || echo "No clang files found"
  exit 1
fi

echo ""
echo "=== Testing CMake ==="
if [ -f "$CMAKE" ]; then
  echo "✅ CMake exists: $CMAKE"
  "$CMAKE" --version | head -3 || echo "CMake version check failed"
else
  echo "❌ CMake not found: $CMAKE"
  echo "Available files in build-tools/cmake/bin:"
  if [ -d "$(dirname "$CMAKE")" ]; then
    ls -la "$(dirname "$CMAKE")" || echo "Cannot list cmake/bin"
  else
    echo "build-tools/cmake/bin directory does not exist"
  fi
  
  echo ""
  echo "Looking for any cmake files:"
  find "$NATIVE_DIR" -name "*cmake*" -type f || echo "No cmake files found"
  exit 1
fi

# Build QEMU
echo "=== Building QEMU ==="
cd ../../third_party/qemu

mkdir -p build
cd build

echo "Environment check:"
echo "CC: $CC"
echo "CXX: $CXX"
echo "SYSROOT: $SYSROOT"

echo ""
echo "=== Running Configure ==="
../configure \
  --target-list=aarch64-softmmu \
  --cc="$CC" \
  --cxx="$CXX" \
  --host-cc="/usr/bin/cc" \
  --cross-prefix="" \
  --extra-cflags="-target aarch64-unknown-linux-ohos --sysroot=${SYSROOT}" \
  --extra-ldflags="-target aarch64-unknown-linux-ohos --sysroot=${SYSROOT}" \
  -Db_staticpic=true \
  -Db_pie=false \
  -Ddefault_library=static \
  -Dtools=disabled \
  --enable-tcg \
  --disable-kvm \
  --disable-xen \
  --disable-werror \
  --enable-vnc \
  --enable-slirp \
  --enable-curl \
  --enable-fdt \
  --enable-guest-agent \
  --enable-vhost-user \
  --enable-vhost-net \
  --enable-keyring \
  --disable-gtk \
  --disable-sdl \
  --disable-vte \
  --disable-curses \
  --disable-brlapi \
  --disable-spice \
  --disable-usb-redir \
  --disable-lzo \
  --disable-snappy \
  --disable-bzip2 \
  --disable-lzfse \
  --disable-zstd \
  --disable-libssh \
  --disable-nettle \
  --disable-gcrypt

echo "✅ Configure completed!"

echo "=== Building QEMU ==="
make -j$(nproc)

echo "✅ QEMU build completed!"

echo "=== Checking build results ==="
ls -la qemu-system-aarch64 || echo "Main binary not found"
find . -name "*.so" -o -name "*.a" | head -10

# Build NAPI module
echo "=== Building NAPI module ==="
cd ../../../entry/src/main/cpp

mkdir -p build
cd build

echo "Using CMake: $CMAKE"
echo "Using CC: $CC"
echo "Using CXX: $CXX"

"$CMAKE" .. \
  -DCMAKE_SYSTEM_NAME=Linux \
  -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
  -DOHOS_NDK_HOME="$OHOS_NDK_HOME" \
  -DSYSROOT="$SYSROOT"

make -j$(nproc)

echo "✅ NAPI module build completed!"

echo "=== Build artifacts ==="
ls -la *.so || echo "No .so files found"
find . -name "*.so" -o -name "*.a"

echo "=== Build completed successfully! ==="
