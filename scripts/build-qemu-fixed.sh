#!/bin/bash
set -euo pipefail

# Fixed QEMU Build Script for HarmonyOS
# Based on the working HNP build configuration

echo "=== Fixed QEMU HarmonyOS Build ==="
echo "Target: aarch64-linux-ohos"
echo ""

# Environment setup - try multiple SDK locations
echo "=== Finding HarmonyOS SDK ==="

# Try different possible SDK locations
SDK_LOCATIONS=(
    "/opt/harmonyos-sdk"
    "/opt/ohos-sdk/linux"
    "$(pwd)/ohos-sdk/linux"
    "$HOME/ohos-sdk/linux"
)

OHOS_NDK_HOME=""

for SDK_ROOT in "${SDK_LOCATIONS[@]}"; do
    echo "Checking: $SDK_ROOT"
    
    if [ -d "$SDK_ROOT" ]; then
        echo "SDK root exists: Yes"
        echo "SDK root contents:"
        ls -la "$SDK_ROOT" 2>/dev/null || echo "Cannot list SDK root"
        
        # Find clang compiler
        CLANG_PATH=$(find "$SDK_ROOT" -name "aarch64-unknown-linux-ohos-clang" -type f 2>/dev/null | head -1)
        if [ -n "$CLANG_PATH" ]; then
            echo "Found clang at: $CLANG_PATH"
            # Get NDK path by going up 3 levels from clang
            NDK_PATH=$(dirname "$CLANG_PATH")
            NDK_PATH=$(dirname "$NDK_PATH")
            NDK_PATH=$(dirname "$NDK_PATH")
            export OHOS_NDK_HOME="$NDK_PATH"
            echo "✅ Found SDK at: $OHOS_NDK_HOME"
            break
        else
            echo "No clang compiler found in $SDK_ROOT"
        fi
    else
        echo "SDK root does not exist: $SDK_ROOT"
    fi
    echo ""
done

if [ -z "$OHOS_NDK_HOME" ]; then
    echo "❌ Error: Could not find HarmonyOS SDK in any of the expected locations"
    echo "Please ensure the SDK is installed at one of:"
    printf '%s\n' "${SDK_LOCATIONS[@]}"
    echo ""
    echo "Or download it using:"
    echo "curl -OL https://repo.huaweicloud.com/openharmony/os/5.1.0-Release/ohos-sdk-windows_linux-public.tar.gz"
    echo "tar -xzf ohos-sdk-windows_linux-public.tar.gz"
    echo "rm -rf ohos-sdk/{ohos,windows}"
    echo "pushd ohos-sdk/linux && for file in \$(find . -type f); do unzip \$file && rm \$file; done && popd"
    exit 1
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

if [ ! -d "$SYSROOT" ]; then
    echo "❌ Error: SYSROOT not found at $SYSROOT"
    exit 1
fi
echo "✅ SYSROOT: $SYSROOT"

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

# Create build directory
rm -rf build_harmonyos_fixed
mkdir -p build_harmonyos_fixed
cd build_harmonyos_fixed

# Configure QEMU with full functionality
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
  --enable-vnc \
  --enable-vnc-jpeg \
  --enable-vnc-png \
  --enable-vnc-sasl \
  --enable-slirp \
  --enable-curl \
  --enable-fdt \
  --enable-guest-agent \
  --enable-vhost-user \
  --enable-vhost-user-blk-server \
  --enable-libvduse \
  --enable-vduse-blk-export \
  --enable-vhost-net \
  --enable-vhost-kernel \
  --enable-keyring \
  --disable-kvm \
  --disable-xen \
  --disable-werror

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

# Create shared library with all dependencies
echo "=== Creating libqemu_full.so with dependencies ==="
$CXX -shared -fPIC -Wl,--no-undefined \
  -target aarch64-unknown-linux-ohos --sysroot=${SYSROOT} \
  -Wl,--whole-archive \
  libqemu-aarch64-softmmu.a \
  libqemuutil.a \
  -Wl,--no-whole-archive \
  # Include dependency libraries
  ../../deps/glib/build/glib/libglib-2.0.a \
  ../../deps/glib/build/gobject/libgobject-2.0.a \
  ../../deps/glib/build/gthread/libgthread-2.0.a \
  ../../deps/glib/build/glib/libcharset/libcharset.a \
  ../../deps/glib/build/glib/gnulib/libgnulib.a \
  ../../deps/pixman/build/pixman/libpixman-1.a \
  ../../deps/pixman/build/pixman/libpixman-arm-neon.a \
  ../../deps/openssl/build/libssl.a \
  ../../deps/openssl/build/libcrypto.a \
  ../../deps/pcre2/build/libpcre2-8.a \
  ../../deps/pcre2/build/libpcre2-posix.a \
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

# Build NAPI module
echo "=== Building NAPI Module ==="
cd ../../../entry/src/main/cpp

# Create build directory
rm -rf build
mkdir -p build
cd build

# Configure with CMake
echo "Configuring NAPI module..."
cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=Linux \
  -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_AR="$AR" \
  -DCMAKE_STRIP="$STRIP" \
  -DCMAKE_RANLIB="$RANLIB" \
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
cp third_party/qemu/build_harmonyos_fixed/libqemu_full.so entry/src/main/libs/arm64-v8a/
cp third_party/qemu/build_harmonyos_fixed/libqemu_full.so entry/src/main/oh_modules/

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
echo "🎉 Fixed build completed successfully!"
echo ""
echo "Note: This build uses the same SDK download method as the working HNP build."
echo "If you still encounter issues, please check the SDK download and extraction process."
