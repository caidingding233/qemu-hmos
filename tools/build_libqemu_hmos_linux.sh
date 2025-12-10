#!/usr/bin/env bash
set -euo pipefail

# Linux 环境下构建 libqemu_hmos.so 的脚本
#
# 系统要求：
# - x86-64 Linux 系统（或 WSL）
# - ARM64 Linux 无法运行 x86-64 版本的 NDK
#
# 推荐使用 WSL（Windows Subsystem for Linux）：
# 1. 在 Windows PowerShell（管理员）中运行：wsl --install
# 2. 安装 Ubuntu 22.04：wsl --install -d Ubuntu-22.04
# 3. 在 WSL 中下载 x86-64 版本的 HarmonyOS NDK
# 4. 运行此脚本进行构建
#
# 详细说明请参考：docs/WSL_BUILD_GUIDE.md

log() {
  printf '[libqemu_hmos-build-linux] %s\n' "$*"
}

error() {
  printf '[libqemu_hmos-build-linux] ERROR: %s\n' "$*" >&2
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

# 检测 OHOS NDK（Linux 路径）
detect_ndk() {
  local candidates=(
    "${OHOS_NDK_HOME:-}"
    "${OHOS_NDK:-}"
    "${REPO_ROOT}/ohos-sdk/linux/native"
    "${HOME}/OpenHarmony/Sdk/18/native"
    "${HOME}/OpenHarmony/Sdk/15/native"
    "/opt/openharmony/ndk/18/native"
    "/opt/openharmony/ndk/15/native"
  )
  for d in "${candidates[@]}"; do
    if [[ -n "${d}" && -d "${d}/llvm/bin" && -d "${d}/sysroot" ]]; then
      echo "${d}"
      return 0
    fi
  done
  return 1
}

# 修复 NDK 中损坏的 clang/clang++ 文件
# 某些版本的 NDK 中 clang/clang++ 只是文本文件而非可执行脚本
fix_ndk_clang() {
  local ndk_dir="$1"
  local llvm_bin="${ndk_dir}/llvm/bin"
  local clang_file="${llvm_bin}/clang"
  local clangpp_file="${llvm_bin}/clang++"
  local clang15_file="${llvm_bin}/clang-15"
  
  # 检查 clang-15 是否存在且可执行
  if [[ ! -x "${clang15_file}" ]]; then
    error "clang-15 不存在或不可执行: ${clang15_file}"
    return 1
  fi
  
  # 检查 clang 文件是否需要修复
  if [[ -f "${clang_file}" ]]; then
    local clang_type
    clang_type=$(file "${clang_file}" 2>/dev/null || echo "unknown")
    
    # 如果 clang 是文本文件（不是 ELF 或脚本），需要修复
    if echo "${clang_type}" | grep -q "ASCII text"; then
      local clang_content
      clang_content=$(cat "${clang_file}" 2>/dev/null || echo "")
      
      # 如果内容只是 "clang-15"，需要修复
      if [[ "${clang_content}" == "clang-15" ]] || [[ ! "${clang_content}" =~ ^#! ]]; then
        log "修复损坏的 clang 文件..."
        cat > "${clang_file}" << 'SCRIPT'
#!/bin/sh
SOURCE=$(dirname -- "$( readlink -f -- "$0"; )")
exec "$SOURCE/clang-15" "$@"
SCRIPT
        chmod +x "${clang_file}"
        log "✅ clang 文件已修复"
      fi
    fi
  fi
  
  # 检查 clang++ 文件是否需要修复
  if [[ -f "${clangpp_file}" ]]; then
    local clangpp_type
    clangpp_type=$(file "${clangpp_file}" 2>/dev/null || echo "unknown")
    
    if echo "${clangpp_type}" | grep -q "ASCII text"; then
      local clangpp_content
      clangpp_content=$(cat "${clangpp_file}" 2>/dev/null || echo "")
      
      # 如果内容只是 "clang" 或没有 shebang
      if [[ "${clangpp_content}" == "clang" ]] || [[ ! "${clangpp_content}" =~ ^#! ]]; then
        log "修复损坏的 clang++ 文件..."
        cat > "${clangpp_file}" << 'SCRIPT'
#!/bin/sh
SOURCE=$(dirname -- "$( readlink -f -- "$0"; )")
exec "$SOURCE/clang-15" "++" "$@"
SCRIPT
        chmod +x "${clangpp_file}"
        log "✅ clang++ 文件已修复"
      fi
    fi
  fi
  
  return 0
}

# 验证编译器是否可用
verify_compiler() {
  local compiler="$1"
  local name="$2"
  
  if [[ ! -f "${compiler}" ]]; then
    error "${name} 不存在: ${compiler}"
    return 1
  fi
  
  if ! "${compiler}" --version >/dev/null 2>&1; then
    error "${name} 无法运行: ${compiler}"
    return 1
fi
  
  log "✅ ${name} 可用: $("${compiler}" --version | head -1)"
  return 0
}

# ========== 主流程 ==========

log "=== 开始构建 libqemu_hmos.so ==="
log ""

# 检查是否在 Linux 环境
if [[ "$(uname)" != "Linux" ]]; then
  log "WARNING: 此脚本设计用于 Linux 环境，当前系统: $(uname)"
  log "继续执行..."
fi

# 检测 NDK
NDK_DIR="$(detect_ndk || true)"
if [[ -z "${NDK_DIR}" ]]; then
  error "未找到 OpenHarmony NDK，请设置 OHOS_NDK_HOME 环境变量。"
  log ""
  log "Linux 上安装 NDK 的方法："
  log "1. 下载 HarmonyOS NDK："
  log "   wget https://repo.huaweicloud.com/openharmony/os/5.1.0-Release/ohos-sdk-windows_linux-public.tar.gz"
  log "2. 解压并设置环境变量："
  log "   tar -xzf ohos-sdk-windows_linux-public.tar.gz"
  log "   export OHOS_NDK_HOME=\$(pwd)/ohos-sdk/linux/native"
  exit 1
fi
log "Using OHOS NDK: ${NDK_DIR}"

# 将 NDK 的 llvm/bin 目录添加到 PATH
export PATH="${NDK_DIR}/llvm/bin:${PATH}"

# 定义编译器路径
CC_WRAPPER="${NDK_DIR}/llvm/bin/aarch64-unknown-linux-ohos-clang"
CXX_WRAPPER="${NDK_DIR}/llvm/bin/aarch64-unknown-linux-ohos-clang++"
AR_BIN="${NDK_DIR}/llvm/bin/llvm-ar"
RANLIB_BIN="${NDK_DIR}/llvm/bin/llvm-ranlib"
STRIP_BIN="${NDK_DIR}/llvm/bin/llvm-strip"
NM_BIN="${NDK_DIR}/llvm/bin/llvm-nm"
OBJCOPY_BIN="${NDK_DIR}/llvm/bin/llvm-objcopy"

# 尝试修复 NDK 中损坏的 clang/clang++ 文件
log ""
log "检查 NDK 编译器..."
fix_ndk_clang "${NDK_DIR}" || true

# 验证编译器
log ""
if ! verify_compiler "${CC_WRAPPER}" "C 编译器"; then
  error "C 编译器验证失败，请检查 NDK 安装"
  exit 1
fi

if ! verify_compiler "${CXX_WRAPPER}" "C++ 编译器"; then
  error "C++ 编译器验证失败，请检查 NDK 安装"
  exit 1
fi

# 输出目录（与 CMakeLists.txt 中的 LIBRARY_OUTPUT_DIRECTORY 一致）
OUTPUT_DIR="${REPO_ROOT}/entry/src/main/libs/arm64-v8a"
mkdir -p "${OUTPUT_DIR}"

# CMake 构建目录
BUILD_DIR="${REPO_ROOT}/entry/src/main/cpp/build-native"
CMAKE_SOURCE_DIR="${REPO_ROOT}/entry/src/main/cpp"

log ""
log "配置 CMake..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

cd "${BUILD_DIR}"

# 检测是否有 Ninja
CMAKE_GENERATOR=""
if command -v ninja >/dev/null 2>&1; then
  CMAKE_GENERATOR="-G Ninja"
  log "使用 Ninja 构建系统"
else
  log "使用默认构建系统（make）"
fi

# 运行 CMake 配置（交叉编译到 HarmonyOS）
# 注意：使用 Linux 作为系统名，因为 CMake 不认识 OHOS
# 但通过 OHOS_NDK_HOME 和 BUILD_FOR_OHOS 标志让 CMakeLists.txt 知道这是 OHOS 构建
cmake "${CMAKE_SOURCE_DIR}" \
  ${CMAKE_GENERATOR} \
  -DCMAKE_SYSTEM_NAME=Linux \
  -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
  -DCMAKE_C_COMPILER="${CC_WRAPPER}" \
  -DCMAKE_CXX_COMPILER="${CXX_WRAPPER}" \
  -DCMAKE_AR="${AR_BIN}" \
  -DCMAKE_RANLIB="${RANLIB_BIN}" \
  -DCMAKE_STRIP="${STRIP_BIN}" \
  -DCMAKE_NM="${NM_BIN}" \
  -DCMAKE_OBJCOPY="${OBJCOPY_BIN}" \
  -DCMAKE_LINKER="${NDK_DIR}/llvm/bin/ld.lld" \
  -DCMAKE_SYSROOT="${NDK_DIR}/sysroot" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DOHOS_NDK_HOME="${NDK_DIR}" \
  -DBUILD_FOR_OHOS=ON \
  -DUSE_PREBUILT_LIB=OFF

log ""
log "编译 libqemu_hmos.so..."
NPROC=$(nproc 2>/dev/null || echo 4)
log "使用 ${NPROC} 个并行任务..."
cmake --build . --parallel "${NPROC}"

# 检查构建产物（CMakeLists.txt 设置输出到 libs/arm64-v8a）
log ""
log "检查构建产物..."

# 可能的输出位置
POSSIBLE_OUTPUTS=(
  "${OUTPUT_DIR}/libqemu_hmos.so"
  "${BUILD_DIR}/libqemu_hmos.so"
)

FOUND_LIB=""
for lib_path in "${POSSIBLE_OUTPUTS[@]}"; do
  if [[ -f "${lib_path}" ]]; then
    FOUND_LIB="${lib_path}"
    break
  fi
done

if [[ -n "${FOUND_LIB}" ]]; then
  # 如果不在目标目录，复制过去
  if [[ "${FOUND_LIB}" != "${OUTPUT_DIR}/libqemu_hmos.so" ]]; then
    cp -f "${FOUND_LIB}" "${OUTPUT_DIR}/libqemu_hmos.so"
    log "已复制库文件到: ${OUTPUT_DIR}/libqemu_hmos.so"
  fi
  
  log ""
  log "✅ 构建成功！"
  log ""
  log "库文件信息："
  ls -lh "${OUTPUT_DIR}/libqemu_hmos.so"
  file "${OUTPUT_DIR}/libqemu_hmos.so"
  
  # 验证是 ARM64 架构
  if command -v readelf >/dev/null 2>&1; then
    log ""
    log "ELF 头信息："
    readelf -h "${OUTPUT_DIR}/libqemu_hmos.so" | grep -E "Class|Machine|Type" || true
  fi
else
  error "未找到构建产物 libqemu_hmos.so"
  log ""
  log "已检查的位置："
  for lib_path in "${POSSIBLE_OUTPUTS[@]}"; do
    log "  - ${lib_path}"
  done
  log ""
  log "构建目录内容："
  ls -la "${BUILD_DIR}" || true
  log ""
  log "检查构建日志: ${BUILD_DIR}/CMakeFiles/CMakeError.log"
  exit 1
fi

log ""
log "=========================================="
log "✅ 构建完成！"
log "=========================================="
log ""
log "预编译库位置: ${OUTPUT_DIR}/libqemu_hmos.so"
log ""
log "下一步："
log "  1. 在 macOS/Windows 上使用 hvigor 构建 HAP"
log "  2. hvigor 会自动使用这个预编译库"
log ""
