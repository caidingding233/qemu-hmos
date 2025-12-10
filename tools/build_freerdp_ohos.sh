#!/usr/bin/env bash
set -euo pipefail

# Build FreeRDP static library for aarch64-linux-ohos
# Output: libfreerdp.a

log() {
  printf '[freerdp-build] %s\n' "$*"
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
SRC_DIR="${REPO_ROOT}/third_party/freerdp/src"
BUILD_DIR="${REPO_ROOT}/third_party/freerdp/build-ohos"
DEST_DIR="${REPO_ROOT}/entry/src/main/cpp/third_party/freerdp"

mkdir -p "${BUILD_DIR}" "${DEST_DIR}"

# Download FreeRDP if not present
if [[ ! -d "${SRC_DIR}" ]]; then
  log "Cloning FreeRDP..."
  git clone --depth=1 https://github.com/FreeRDP/FreeRDP.git "${SRC_DIR}"
fi

# Check for OpenSSL (required dependency)
OPENSSL_PREFIX="${REPO_ROOT}/third_party/deps/install-ohos"
if [[ ! -d "${OPENSSL_PREFIX}/lib" ]] || [[ ! -f "${OPENSSL_PREFIX}/lib/libssl.a" ]]; then
  log "⚠️  Warning: OpenSSL not found at ${OPENSSL_PREFIX}"
  log "   Please run tools/build_openssl_ohos.sh first"
  OPENSSL_PREFIX=""
else
  log "✅ Found OpenSSL at ${OPENSSL_PREFIX}"
fi

log "Configuring FreeRDP..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# Find ZLIB in sysroot
ZLIB_LIB="${SYSROOT}/usr/lib/aarch64-linux-ohos/libz.so"
ZLIB_INCLUDE="${SYSROOT}/usr/include"

CMAKE_ARGS=(
  -S "${SRC_DIR}"
  -B "${BUILD_DIR}"
  -DCMAKE_SYSTEM_NAME=Linux
  -DCMAKE_SYSTEM_PROCESSOR=aarch64
  -DCMAKE_C_COMPILER="${CLANG_BIN}"
  -DCMAKE_CXX_COMPILER="${CXX_BIN}"
  -DCMAKE_AR="${AR_BIN}"
  -DCMAKE_RANLIB="${RANLIB_BIN}"
  -DCMAKE_SYSROOT="${SYSROOT}"
  -DCMAKE_C_FLAGS="--target=${CROSS_TRIPLE} --sysroot=${SYSROOT} -fPIC -D__MUSL__"
  -DCMAKE_CXX_FLAGS="--target=${CROSS_TRIPLE} --sysroot=${SYSROOT} -fPIC -D__MUSL__"
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
  -DCMAKE_FIND_ROOT_PATH="${SYSROOT}"
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
  -DBUILD_SHARED_LIBS=OFF
  -DWITH_CLIENT=OFF
  -DWITH_CLIENT_COMMON=OFF
  -DWITH_SERVER=OFF
  -DWITH_X11=OFF
  -DWITH_WAYLAND=OFF
  -DWITH_ALSA=OFF
  -DWITH_PULSE=OFF
  -DWITH_OSS=OFF
  -DWITH_CUPS=OFF
  -DWITH_PCSC=OFF
  -DWITH_FFMPEG=OFF
  -DWITH_GSSAPI=OFF
  -DWITH_JPEG=OFF
  -DWITH_MANPAGES=OFF
  -DWITH_SSE2=OFF
  -DWITH_KRB5=OFF
  -DWITH_URIPARSER=OFF
  -DWITH_JSONC=OFF
  -DWITH_SYSTEMD=OFF
  -DWITH_ICU=OFF
  -DWITH_CHANNELS=OFF
  -DWITH_PROXY=OFF
  -DWITH_PROXY_MODULES=OFF
  -DWITH_WINPR_ICU=OFF
  -DWITH_WINPR_TOOLS=OFF
  -DWITH_WINPR_DEPRECATED=OFF
  -DWITH_SWSCALE=OFF
  -DWITH_CODECS=OFF
  -DZLIB_LIBRARY="${ZLIB_LIB}"
  -DZLIB_INCLUDE_DIR="${ZLIB_INCLUDE}"
)

if [[ -n "${OPENSSL_PREFIX}" ]]; then
  CMAKE_ARGS+=(
    -DWITH_OPENSSL=ON
    -DOPENSSL_ROOT_DIR="${OPENSSL_PREFIX}"
    -DOPENSSL_INCLUDE_DIR="${OPENSSL_PREFIX}/include"
    -DOPENSSL_CRYPTO_LIBRARY="${OPENSSL_PREFIX}/lib/libcrypto.a"
    -DOPENSSL_SSL_LIBRARY="${OPENSSL_PREFIX}/lib/libssl.a"
  )
else
  CMAKE_ARGS+=(-DWITH_OPENSSL=OFF)
fi

cmake "${CMAKE_ARGS[@]}"

log "Building FreeRDP..."
cmake --build "${BUILD_DIR}" --parallel

# Find and copy libfreerdp.a
log "Searching for libfreerdp.a..."
FREERDP_LIB=$(find "${BUILD_DIR}" -name "libfreerdp*.a" -type f | head -1)

if [[ -z "${FREERDP_LIB}" ]]; then
  log "⚠️  Warning: libfreerdp.a not found in build directory"
  log "   Build directory contents:"
  find "${BUILD_DIR}" -name "*.a" -type f | head -10
  exit 1
fi

cp -f "${FREERDP_LIB}" "${DEST_DIR}/libfreerdp.a"
log "✅ Copied libfreerdp.a to ${DEST_DIR}"

# Also copy libwinpr.a if found (dependency)
WINPR_LIB=$(find "${BUILD_DIR}" -name "libwinpr*.a" -type f | head -1)
if [[ -n "${WINPR_LIB}" ]]; then
  cp -f "${WINPR_LIB}" "${DEST_DIR}/libwinpr.a"
  log "✅ Copied libwinpr.a to ${DEST_DIR}"
fi

log "Done! Output:"
ls -lh "${DEST_DIR}"/*.a 2>/dev/null || true

