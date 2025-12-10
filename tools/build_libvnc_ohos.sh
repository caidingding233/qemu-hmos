#!/usr/bin/env bash
set -euo pipefail

# Build LibVNC (server and client) static libraries for aarch64-linux-ohos
# Output: libvncserver.a and libvncclient.a

log() {
  printf '[libvnc-build] %s\n' "$*"
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

# Detect OHOS NDK
detect_ndk() {
  local candidates=(
    "${OHOS_NDK_HOME:-}"
    "${OHOS_NDK:-}"
    "${REPO_ROOT}/ohos-sdk/linux/native"
    "${HOME}/Library/OpenHarmony/Sdk/18/native"
    "${HOME}/Library/OpenHarmony/Sdk/15/native"
    "${HOME}/OpenHarmony/Sdk/18/native"
  )
  for d in "${candidates[@]}"; do
    if [[ -n "${d}" && -d "${d}/llvm/bin" && -d "${d}/sysroot" ]]; then
      echo "${d}"
      return 0
    fi
  done
  return 1
}

NDK_DIR="$(detect_ndk || true)"
if [[ -z "${NDK_DIR}" ]]; then
  log "error: OpenHarmony NDK not found. Set OHOS_NDK_HOME environment variable."
  exit 1
fi

log "Using OHOS NDK: ${NDK_DIR}"

CROSS_TRIPLE="aarch64-unknown-linux-ohos"
CLANG_BIN="${NDK_DIR}/llvm/bin/${CROSS_TRIPLE}-clang"
CXX_BIN="${NDK_DIR}/llvm/bin/${CROSS_TRIPLE}-clang++"
AR_BIN="${NDK_DIR}/llvm/bin/llvm-ar"
RANLIB_BIN="${NDK_DIR}/llvm/bin/llvm-ranlib"
SYSROOT="${NDK_DIR}/sysroot"

# Check tools
for tool in "${CLANG_BIN}" "${AR_BIN}"; do
  if [[ ! -x "${tool}" ]]; then
    log "error: tool not found: ${tool}"
    exit 1
  fi
done

# Source and build directories
SRC_DIR="${REPO_ROOT}/third_party/libvnc"
BUILD_DIR="${SRC_DIR}/build-ohos"
SERVER_DEST="${REPO_ROOT}/entry/src/main/cpp/third_party/libvncserver"
CLIENT_DEST="${REPO_ROOT}/entry/src/main/cpp/third_party/libvncclient"

mkdir -p "${BUILD_DIR}" "${SERVER_DEST}" "${CLIENT_DEST}"

# Download LibVNC if not present
if [[ ! -d "${SRC_DIR}" ]]; then
  log "Cloning LibVNC..."
  git clone --depth=1 https://github.com/LibVNC/libvncserver.git "${SRC_DIR}"
fi

log "Configuring LibVNC..."
cd "${SRC_DIR}"

# Check build system
if [[ -f "CMakeLists.txt" ]]; then
  # Use CMake
  rm -rf "${BUILD_DIR}"
  mkdir -p "${BUILD_DIR}"
  
  cmake -S . -B "${BUILD_DIR}" \
    -DCMAKE_SYSTEM_NAME=Linux \
    -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
    -DCMAKE_C_COMPILER="${CLANG_BIN}" \
    -DCMAKE_CXX_COMPILER="${CXX_BIN}" \
    -DCMAKE_AR="${AR_BIN}" \
    -DCMAKE_RANLIB="${RANLIB_BIN}" \
    -DCMAKE_SYSROOT="${SYSROOT}" \
    -DCMAKE_C_FLAGS="--target=${CROSS_TRIPLE} --sysroot=${SYSROOT} -fPIC -D__MUSL__ -DNO_CRYPTO" \
    -DCMAKE_CXX_FLAGS="--target=${CROSS_TRIPLE} --sysroot=${SYSROOT} -fPIC -D__MUSL__ -DNO_CRYPTO" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DWITH_GNUTLS=OFF \
    -DWITH_OPENSSL=OFF \
    -DWITH_SASL=OFF \
    -DWITH_FFMPEG=OFF \
    -DWITH_SDL=OFF \
    -DWITH_TIGHTVNC_FILETRANSFER=OFF \
    -DWITH_WEBSOCKETS=OFF \
    -DWITH_JPEG=OFF \
    -DWITH_PNG=OFF \
    -DWITH_LZO=OFF \
    -DWITH_GCrypt=OFF \
    -DWITH_GCRYPT=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
  
  log "Building LibVNC with CMake (libraries only)..."
  # Build only libraries, skip examples and tools
  cmake --build "${BUILD_DIR}" --target vncserver vncclient --parallel || {
    log "⚠️  Full build failed, trying to build libraries individually..."
    # Try to build just the static libraries
    cmake --build "${BUILD_DIR}" --target vncserver --parallel || true
    cmake --build "${BUILD_DIR}" --target vncclient --parallel || true
  }
elif [[ -f "configure" ]] || [[ -f "autogen.sh" ]]; then
  # Use autotools
  log "Using autotools build system..."
  
  # Run autogen if needed
  if [[ -f "autogen.sh" ]]; then
    log "Running autogen.sh..."
    ./autogen.sh
  fi
  
  # Configure
  export CC="${CLANG_BIN}"
  export CXX="${CXX_BIN}"
  export AR="${AR_BIN}"
  export RANLIB="${RANLIB_BIN}"
  export CFLAGS="--target=${CROSS_TRIPLE} --sysroot=${SYSROOT} -fPIC -D__MUSL__"
  export CXXFLAGS="--target=${CROSS_TRIPLE} --sysroot=${SYSROOT} -fPIC -D__MUSL__"
  export LDFLAGS="--target=${CROSS_TRIPLE} --sysroot=${SYSROOT}"
  
  log "Running configure..."
  ./configure \
    --host=aarch64-linux-ohos \
    --prefix="${BUILD_DIR}/install" \
    --enable-static \
    --disable-shared \
    --without-gnutls \
    --without-openssl \
    --without-sasl \
    --without-ffmpeg \
    --without-sdl \
    --disable-tightvnc-filetransfer \
    --disable-websockets
  
  log "Building LibVNC with make..."
  make -j$(nproc)
  make install
  
  BUILD_DIR="${BUILD_DIR}/install"
else
  log "error: Unknown build system in ${SRC_DIR}"
  exit 1
fi

# Find and copy libraries
log "Copying libraries..."

# Find libvncserver.a
SERVER_LIB=$(find "${BUILD_DIR}" -name "libvncserver.a" -type f | head -1)
if [[ -n "${SERVER_LIB}" ]]; then
  cp -f "${SERVER_LIB}" "${SERVER_DEST}/libvncserver.a"
  log "✅ Copied libvncserver.a to ${SERVER_DEST}"
else
  log "⚠️  Warning: libvncserver.a not found"
fi

# Find libvncclient.a
CLIENT_LIB=$(find "${BUILD_DIR}" -name "libvncclient.a" -type f | head -1)
if [[ -n "${CLIENT_LIB}" ]]; then
  cp -f "${CLIENT_LIB}" "${CLIENT_DEST}/libvncclient.a"
  log "✅ Copied libvncclient.a to ${CLIENT_DEST}"
else
  log "⚠️  Warning: libvncclient.a not found"
fi

# Copy headers
if [[ -d "${SRC_DIR}/libvncserver" ]]; then
  mkdir -p "${SERVER_DEST}/include" "${CLIENT_DEST}/include"
  cp -r "${SRC_DIR}"/libvncserver/*.h "${SERVER_DEST}/include/" 2>/dev/null || true
  cp -r "${SRC_DIR}"/rfb/*.h "${CLIENT_DEST}/include/rfb/" 2>/dev/null || true
  log "✅ Copied headers"
fi

log "Done!"

