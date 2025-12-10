#!/usr/bin/env bash
set -euo pipefail

# 独立构建 libqemu_hmos.so 的脚本
# 这个库应该提前编译好，放在 entry/src/main/libs/arm64-v8a/ 目录下
# hvigor 构建时只需要复制和打包，不需要现场编译

log() {
  printf '[libqemu_hmos-build] %s\n' "$*"
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

# 检测 OHOS NDK
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
  log "ERROR: 未找到 OpenHarmony NDK，请设置 OHOS_NDK_HOME 环境变量。" >&2
  exit 1
fi
log "Using OHOS NDK: ${NDK_DIR}"

# 输出目录
OUTPUT_DIR="${REPO_ROOT}/entry/src/main/libs/arm64-v8a"
mkdir -p "${OUTPUT_DIR}"

# CMake 构建目录
BUILD_DIR="${REPO_ROOT}/entry/src/main/cpp/build-native"
CMAKE_SOURCE_DIR="${REPO_ROOT}/entry/src/main/cpp"

log "配置 CMake..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

cd "${BUILD_DIR}"

# 运行 CMake 配置
cmake "${CMAKE_SOURCE_DIR}" \
  -DCMAKE_SYSTEM_NAME=Linux \
  -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
  -DCMAKE_C_COMPILER="${NDK_DIR}/llvm/bin/aarch64-unknown-linux-ohos-clang" \
  -DCMAKE_CXX_COMPILER="${NDK_DIR}/llvm/bin/aarch64-unknown-linux-ohos-clang++" \
  -DCMAKE_AR="${NDK_DIR}/llvm/bin/llvm-ar" \
  -DCMAKE_RANLIB="${NDK_DIR}/llvm/bin/llvm-ranlib" \
  -DCMAKE_SYSROOT="${NDK_DIR}/sysroot" \
  -DCMAKE_BUILD_TYPE=Release \
  -DOHOS_NDK_HOME="${NDK_DIR}" \
  -DBUILD_FOR_OHOS=ON \
  -DUSE_PREBUILT_LIB=OFF

log "编译 libqemu_hmos.so..."
cmake --build . --parallel

# 复制到输出目录
if [[ -f "${BUILD_DIR}/libqemu_hmos.so" ]]; then
  cp -f "${BUILD_DIR}/libqemu_hmos.so" "${OUTPUT_DIR}/libqemu_hmos.so"
  log "✅ 成功构建并复制到: ${OUTPUT_DIR}/libqemu_hmos.so"
  ls -lh "${OUTPUT_DIR}/libqemu_hmos.so"
else
  log "❌ 错误: 未找到构建产物 libqemu_hmos.so"
  exit 1
fi

log "完成！"
log "预编译库位置: ${OUTPUT_DIR}/libqemu_hmos.so"
log ""
log "提示: 现在 hvigor 构建时会自动使用这个预编译库，不需要现场编译。"

