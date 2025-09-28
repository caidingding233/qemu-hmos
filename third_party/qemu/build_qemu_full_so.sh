#!/bin/bash
set -euo pipefail

# 切换到脚本所在目录
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"

echo "=== 链接 QEMU 静态归档为 libqemu_full.so (OHOS) ==="

export OHOS_NDK_HOME="/Users/caidingding233/Library/OpenHarmony/Sdk/18/native"
export SYSROOT="${OHOS_NDK_HOME}/sysroot"
export CXX="${OHOS_NDK_HOME}/llvm/bin/aarch64-unknown-linux-ohos-clang++"
export STRIP="${OHOS_NDK_HOME}/llvm/bin/llvm-strip"

BUILD_DIR="build_harmonyos_full"
OUT_SO="libqemu_full.so"

if [ ! -d "$BUILD_DIR" ]; then
  echo "Build dir $BUILD_DIR not found. Please run build_harmonyos_full.sh first." >&2
  exit 1
fi

cd "$BUILD_DIR"

# 核心静态库
ARCHS=(
  libqemu-aarch64-softmmu.a
  libqemuutil.a
  subprojects/dtc/libfdt/libfdt.a
  subprojects/berkeley-softfloat-3/libsoftfloat.a
)

LINK_ARGS=(
  "-shared" "-fPIC" "-Wl,--no-undefined"
  "-target" "aarch64-unknown-linux-ohos" "--sysroot=${SYSROOT}"
  "-Wl,--whole-archive"
)

for a in "${ARCHS[@]}"; do
  if [ -f "$a" ]; then LINK_ARGS+=("$a"); else echo "WARN: missing $a"; fi
done

LINK_ARGS+=("-Wl,--no-whole-archive")

# 常见系统依赖（需存在于 sysroot）
LINK_ARGS+=(
  -lpthread -ldl -lm -lz -lzstd -lpng -ljpeg -lgnutls
  -lglib-2.0 -lgio-2.0 -lgobject-2.0 -lpixman-1
)

"${CXX}" ${LINK_ARGS[@]} -o "${OUT_SO}"
"${STRIP}" -S "${OUT_SO}" || true

APP_LIBS_ARCH="../../entry/src/main/cpp/libs/arm64-v8a"
APP_LIBS_ROOT="../../entry/src/main/cpp/libs"
mkdir -p "${APP_LIBS_ARCH}" "${APP_LIBS_ROOT}"
cp -f "${OUT_SO}" "${APP_LIBS_ARCH}/"
cp -f "${OUT_SO}" "${APP_LIBS_ROOT}/"

echo "Done: ${APP_LIBS_ARCH}/${OUT_SO} and ${APP_LIBS_ROOT}/${OUT_SO}"

