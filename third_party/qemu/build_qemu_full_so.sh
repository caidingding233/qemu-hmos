#!/bin/bash
set -euo pipefail

# 切换到脚本所在目录
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"

echo "=== 链接 QEMU 静态归档为 libqemu_full.so (Linux本地) ==="

# 检查Linux环境
if [[ "$(uname)" != "Linux" ]]; then
  echo "❌ 此脚本专为Linux主机设计，请在Linux机器上运行。"
  exit 1
fi

# 安装系统依赖
echo "=== 安装系统依赖 ==="
sudo apt update
sudo apt install -y \
  build-essential cmake curl wget unzip python3 git \
  libglib2.0-dev libpixman-1-dev libssl-dev \
  libcurl4-openssl-dev libssh-dev libgnutls28-dev \
  libsasl2-dev libpam0g-dev libbz2-dev libzstd-dev \
  libpcre2-dev pkg-config meson ninja-build tree \
  binutils-aarch64-linux-gnu gcc-aarch64-linux-gnu \
  libc6-dev libc6-dev-arm64-cross

# 自动检测NDK路径
export OHOS_NDK_HOME=""
for candidate in \
  "${SCRIPT_DIR}/../../ohos-sdk/linux/native" \
  "${HOME}/Library/OpenHarmony/Sdk/18/native" \
  "${HOME}/OpenHarmony/Sdk/18/native" \
  "${HOME}/openharmony/sdk/18/native"; do
  if [ -d "${candidate}" ]; then
    export OHOS_NDK_HOME="${candidate}"
    break
  fi
done

if [ -z "${OHOS_NDK_HOME:-}" ]; then
  echo "error: set OHOS_NDK_HOME to your OpenHarmony NDK (native) directory" >&2
  exit 1
fi

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

APP_LIBS_ARCH="../../entry/src/main/libs/arm64-v8a"
APP_LIBS_ROOT="../../entry/src/main/libs"
mkdir -p "${APP_LIBS_ARCH}" "${APP_LIBS_ROOT}"
cp -f "${OUT_SO}" "${APP_LIBS_ARCH}/"
cp -f "${OUT_SO}" "${APP_LIBS_ROOT}/"

echo "Done: ${APP_LIBS_ARCH}/${OUT_SO} and ${APP_LIBS_ROOT}/${OUT_SO}"
echo "✅ 编译完成! .so文件在 entry/src/main/libs/arm64-v8a/"
echo "检查: ls entry/src/main/libs/arm64-v8a/libqemu_full.so"

