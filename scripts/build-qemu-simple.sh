#!/bin/bash
set -euo pipefail

# Simplified QEMU Build Script for HarmonyOS
# This script builds QEMU without problematic submodules

echo "=== Simplified QEMU HarmonyOS Build ==="
echo "Target: aarch64-linux-ohos"
echo ""

# Environment setup - dynamically find SDK paths
echo "=== Finding HarmonyOS SDK ==="
SDK_ROOT="/opt/harmonyos-sdk"

# Try different possible SDK structures
if [ -d "$SDK_ROOT/sdk/default/openharmony/native" ]; then
    export OHOS_NDK_HOME="$SDK_ROOT/sdk/default/openharmony/native"
    echo "Found SDK at: $OHOS_NDK_HOME"
elif [ -d "$SDK_ROOT/default/openharmony/native" ]; then
    export OHOS_NDK_HOME="$SDK_ROOT/default/openharmony/native"
    echo "Found SDK at: $OHOS_NDK_HOME"
else
    echo "Searching for NDK structure..."
    NDK_PATH=$(find $SDK_ROOT -name "aarch64-unknown-linux-ohos-clang" -type f | head -1 | xargs dirname | xargs dirname | xargs dirname)
    if [ -n "$NDK_PATH" ]; then
        export OHOS_NDK_HOME="$NDK_PATH"
        echo "Found SDK at: $OHOS_NDK_HOME"
    else
        echo "❌ Error: Could not find HarmonyOS NDK"
        exit 1
    fi
fi

export SYSROOT="${OHOS_NDK_HOME}/sysroot"
export CC="${OHOS_NDK_HOME}/llvm/bin/aarch64-unknown-linux-ohos-clang"
export CXX="${OHOS_NDK_HOME}/llvm/bin/aarch64-unknown-linux-ohos-clang++"
export AR="${OHOS_NDK_HOME}/llvm/bin/llvm-ar"
export STRIP="${OHOS_NDK_HOME}/llvm/bin/llvm-strip"
export RANLIB="${OHOS_NDK_HOME}/llvm/bin/llvm-ranlib"
export LD="${OHOS_NDK_HOME}/llvm/bin/ld.lld"

# Verify environment
echo "=== Environment Check ==="
if [ ! -f "$CC" ]; then
    echo "❌ Error: CC not found at $CC"
    exit 1
fi
echo "✅ CC: $CC"

if [ ! -f "$CXX" ]; then
    echo "❌ Error: CXX not found at $CXX"
    exit 1
fi
echo "✅ CXX: $CXX"

echo "✅ Environment verified"
echo ""

# Clean and prepare QEMU build
echo "=== Preparing QEMU Build ==="
cd third_party/qemu

# Remove problematic submodules and use system libraries
echo "Cleaning submodules..."
rm -rf subprojects/berkeley-softfloat-3
rm -rf subprojects/dtc
rm -rf subprojects/libvncserver
rm -rf subprojects/libvncclient

# Create minimal build directory
rm -rf build_harmonyos_simple
mkdir -p build_harmonyos_simple
cd build_harmonyos_simple

# Configure QEMU with minimal dependencies
echo "Configuring QEMU..."
../configure \
  --target-list=aarch64-softmmu \
  --cross-prefix=aarch64-unknown-linux-ohos- \
  --cc="$CC" \
  --host-cc="/usr/bin/cc" \
  --extra-cflags="-target aarch64-unknown-linux-ohos --sysroot=${SYSROOT}" \
  --extra-ldflags="-target aarch64-unknown-linux-ohos --sysroot=${SYSROOT}" \
  -Db_staticpic=true \
  -Db_pie=false \
  -Ddefault_library=static \
  -Dtools=disabled \
  --enable-tcg \
  --disable-fdt \
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
  --disable-ssh

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

# Create minimal shared library
echo "=== Creating libqemu_full.so ==="
$CXX -shared -fPIC -Wl,--no-undefined \
  -target aarch64-unknown-linux-ohos --sysroot=${SYSROOT} \
  -Wl,--whole-archive \
  libqemu-aarch64-softmmu.a \
  libqemuutil.a \
  -Wl,--no-whole-archive \
  -lpthread -ldl -lm -lz \
  -o libqemu_full.so

# Strip debug symbols
$STRIP -S libqemu_full.so

# Verify the shared library
if [ ! -f "libqemu_full.so" ]; then
    echo "❌ Error: libqemu_full.so not created"
    exit 1
fi

echo "✅ libqemu_full.so created successfully"
echo ""

# Build minimal NAPI module
echo "=== Building NAPI Module ==="
cd ../../../entry/src/main/cpp

# Create build directory
rm -rf build
mkdir -p build
cd build

# Create minimal CMakeLists.txt for testing
cat > ../CMakeLists_minimal.txt << 'EOF'
cmake_minimum_required(VERSION 3.5)
project(qemu_hmos_minimal VERSION 1.0.0)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Set HarmonyOS toolchain
set(CMAKE_C_COMPILER "$ENV{CC}")
set(CMAKE_CXX_COMPILER "$ENV{CXX}")
set(CMAKE_AR "$ENV{AR}")
set(CMAKE_STRIP "$ENV{STRIP}")
set(CMAKE_RANLIB "$ENV{RANLIB}")

# Create minimal NAPI module
add_library(qemu_hmos_minimal SHARED napi_init.cpp)

# Set output properties
set_target_properties(qemu_hmos_minimal PROPERTIES
    OUTPUT_NAME "qemu_hmos"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../libs/arm64-v8a"
)
EOF

# Configure with minimal CMake
echo "Configuring minimal NAPI module..."
cmake -f ../CMakeLists_minimal.txt \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSROOT="$SYSROOT" \
  -DCMAKE_FIND_ROOT_PATH="$SYSROOT" \
  -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY

# Build NAPI module
echo "Building NAPI module..."
make -j$(nproc)

# Verify NAPI module
if [ ! -f "libqemu_hmos.so" ]; then
    echo "❌ Error: libqemu_hmos.so not created"
    exit 1
fi

echo "✅ NAPI module built successfully"
echo ""

# Copy libraries to target directories
echo "=== Copying Libraries ==="
cd ../../../../..

# Create target directories
mkdir -p entry/src/main/libs/arm64-v8a
mkdir -p entry/src/main/oh_modules

# Copy QEMU full library
cp third_party/qemu/build_harmonyos_simple/libqemu_full.so entry/src/main/libs/arm64-v8a/
cp third_party/qemu/build_harmonyos_simple/libqemu_full.so entry/src/main/oh_modules/

# Copy NAPI module
cp entry/src/main/cpp/build/libqemu_hmos.so entry/src/main/libs/arm64-v8a/

echo "✅ Libraries copied successfully"
echo ""

# Final verification
echo "=== Final Verification ==="
echo "Generated libraries:"
ls -la entry/src/main/libs/arm64-v8a/
echo ""
echo "Library sizes:"
du -h entry/src/main/libs/arm64-v8a/*
echo ""
echo "Library types:"
file entry/src/main/libs/arm64-v8a/*
echo ""
echo "🎉 Simplified build completed successfully!"
echo ""
echo "Note: This is a minimal build for testing purposes."
echo "For full functionality, you may need to add back specific features."
