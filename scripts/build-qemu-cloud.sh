#!/bin/bash
set -euo pipefail

# QEMU HarmonyOS Cloud Build Script
# This script builds QEMU for HarmonyOS in a cloud environment

echo "=== QEMU HarmonyOS Cloud Build Script ==="
echo "Target: aarch64-linux-ohos"
echo "QEMU Version: 8.2.0"
echo "HarmonyOS SDK: 6.0.0.848"
echo ""

# Environment setup
export OHOS_NDK_HOME="/opt/harmonyos-sdk/sdk/default/openharmony/native"
export SYSROOT="${OHOS_NDK_HOME}/sysroot"
export CC="${OHOS_NDK_HOME}/llvm/bin/aarch64-unknown-linux-ohos-clang"
export CXX="${OHOS_NDK_HOME}/llvm/bin/aarch64-unknown-linux-ohos-clang++"
export AR="${OHOS_NDK_HOME}/llvm/bin/llvm-ar"
export STRIP="${OHOS_NDK_HOME}/llvm/bin/llvm-strip"
export RANLIB="${OHOS_NDK_HOME}/llvm/bin/llvm-ranlib"
export LD="${OHOS_NDK_HOME}/llvm/bin/ld.lld"
export CMAKE="${OHOS_NDK_HOME}/build-tools/cmake/bin/cmake"

# Verify environment
echo "=== Environment Verification ==="
echo "OHOS_NDK_HOME: $OHOS_NDK_HOME"
echo "CC: $CC"
echo "CXX: $CXX"
echo "CMAKE: $CMAKE"
echo ""

# Check if tools exist
if [ ! -f "$CC" ]; then
    echo "❌ Error: CC not found at $CC"
    exit 1
fi

if [ ! -f "$CXX" ]; then
    echo "❌ Error: CXX not found at $CXX"
    exit 1
fi

if [ ! -f "$CMAKE" ]; then
    echo "❌ Error: CMAKE not found at $CMAKE"
    exit 1
fi

echo "✅ All tools found"
echo ""

# Build QEMU
echo "=== Building QEMU ==="
cd third_party/qemu

# Clean previous build
rm -rf build_harmonyos_full
mkdir -p build_harmonyos_full
cd build_harmonyos_full

# Configure QEMU
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
  --enable-fdt=internal \
  --disable-kvm \
  --disable-xen \
  --disable-werror \
  -Dvhost_user=disabled \
  -Dvhost_user_blk_server=disabled \
  -Dlibvduse=disabled \
  -Dvduse_blk_export=disabled \
  -Dvhost_net=disabled \
  -Dvhost_kernel=disabled \
  -Dkeyring=disabled \
  -Dguest_agent=disabled

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

if [ ! -f "qemu-system-aarch64" ]; then
    echo "❌ Error: qemu-system-aarch64 not found"
    exit 1
fi

echo "✅ QEMU build successful"
echo ""

# Create libqemu_full.so
echo "=== Creating libqemu_full.so ==="
$CXX -shared -fPIC -Wl,--no-undefined \
  -target aarch64-unknown-linux-ohos --sysroot=${SYSROOT} \
  -Wl,--whole-archive \
  libqemu-aarch64-softmmu.a \
  libqemuutil.a \
  subprojects/dtc/libfdt/libfdt.a \
  subprojects/berkeley-softfloat-3/libsoftfloat.a \
  -Wl,--no-whole-archive \
  -lpthread -ldl -lm -lz -lzstd -lpng -ljpeg -lgnutls \
  -lglib-2.0 -lgio-2.0 -lgobject-2.0 -lpixman-1 \
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

# Clean previous build
rm -rf build
mkdir -p build
cd build

# Configure with CMake
echo "Configuring NAPI module..."
$CMAKE .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_AR="$AR" \
  -DCMAKE_STRIP="$STRIP" \
  -DCMAKE_RANLIB="$RANLIB" \
  -DCMAKE_SYSROOT="$SYSROOT" \
  -DCMAKE_FIND_ROOT_PATH="$SYSROOT" \
  -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY

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
cp third_party/qemu/build_harmonyos_full/libqemu_full.so entry/src/main/libs/arm64-v8a/
cp third_party/qemu/build_harmonyos_full/libqemu_full.so entry/src/main/oh_modules/

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
echo "NAPI symbols:"
nm -D entry/src/main/libs/arm64-v8a/libqemu_hmos.so | grep -E "(napi|NAPI)" | head -5
echo ""
echo "🎉 Build completed successfully!"
echo ""
echo "Next steps:"
echo "1. Commit the generated libraries"
echo "2. Test the NAPI module loading"
echo "3. Build the HarmonyOS application"
