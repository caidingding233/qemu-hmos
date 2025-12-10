#!/usr/bin/env bash
# 检查 Linux 上 NDK 的兼容性

echo "=== 检查 NDK 兼容性 ==="

NDK_DIR="${OHOS_NDK_HOME:-}"
if [ -z "$NDK_DIR" ]; then
  echo "请设置 OHOS_NDK_HOME 环境变量"
  exit 1
fi

CLANG="$NDK_DIR/llvm/bin/aarch64-unknown-linux-ohos-clang"
CLANG_BIN="$NDK_DIR/llvm/bin/clang"

echo "检查编译器："
echo "  CLANG wrapper: $CLANG"
echo "  CLANG binary: $CLANG_BIN"

if [ -f "$CLANG" ]; then
  echo "✅ CLANG wrapper 存在"
  file "$CLANG" | head -1
else
  echo "❌ CLANG wrapper 不存在"
fi

if [ -f "$CLANG_BIN" ]; then
  echo "✅ CLANG binary 存在"
  file "$CLANG_BIN" | head -1
  
  # 如果是符号链接，检查实际文件
  if [ -L "$CLANG_BIN" ]; then
    REAL_CLANG=$(readlink -f "$CLANG_BIN")
    echo "  实际文件: $REAL_CLANG"
    if [ -f "$REAL_CLANG" ]; then
      echo "  实际文件格式:"
      file "$REAL_CLANG" | head -1
      CLANG_BIN="$REAL_CLANG"
    fi
  fi
  
  # 检查是否是 macOS 二进制文件
  if file "$CLANG_BIN" | grep -q "Mach-O"; then
    echo "❌ 错误：CLANG 是 macOS 版本的，无法在 Linux 上运行"
    echo ""
    echo "解决方案："
    echo "1. 下载 Linux 版本的 HarmonyOS NDK"
    echo "2. 或者使用 Docker 容器在 Linux 上运行 macOS 二进制文件（不推荐）"
    echo ""
    echo "下载链接："
    echo "https://repo.huaweicloud.com/openharmony/os/5.1.0-Release/ohos-sdk-windows_linux-public.tar.gz"
  elif file "$CLANG_BIN" | grep -q "ELF"; then
    echo "✅ CLANG 是 Linux 版本的（ELF 格式）"
    
    # 尝试运行测试
    echo ""
    echo "测试编译器是否能运行："
    SYSTEM_ARCH=$(uname -m)
    COMPILER_ARCH=$(file "$CLANG_BIN" | grep -oE "x86-64|aarch64|arm64|i386|i686" | head -1 || echo "未知")
    
    if [ "$SYSTEM_ARCH" != "$COMPILER_ARCH" ] && [ "$COMPILER_ARCH" != "未知" ]; then
      echo "❌ 架构不匹配！"
      echo "   当前系统架构: $SYSTEM_ARCH"
      echo "   编译器架构: $COMPILER_ARCH"
      echo ""
      echo "解决方案："
      if [ "$SYSTEM_ARCH" = "aarch64" ] && [ "$COMPILER_ARCH" = "x86-64" ]; then
        echo "1. 在 x86-64 Linux 系统上编译（推荐）"
        echo "   - 使用 x86-64 的 Linux 虚拟机或容器"
        echo "   - 或者在 x86-64 的物理机上编译"
        echo ""
        echo "2. 下载 ARM64 版本的 HarmonyOS NDK（如果存在）"
        echo "   - 检查华为云仓库是否有 ARM64 版本的 NDK"
        echo ""
        echo "3. 使用交叉编译工具链（如果可用）"
        echo "   - 某些情况下可以使用 qemu-user 模拟 x86-64"
      elif [ "$SYSTEM_ARCH" = "x86_64" ] && [ "$COMPILER_ARCH" = "aarch64" ]; then
        echo "1. 下载 x86-64 版本的 HarmonyOS NDK"
        echo "2. 或者在 ARM64 系统上编译"
      fi
      echo ""
      echo "当前 NDK 下载链接（x86-64 版本）："
      echo "https://repo.huaweicloud.com/openharmony/os/5.1.0-Release/ohos-sdk-windows_linux-public.tar.gz"
    elif "$CLANG_BIN" --version >/dev/null 2>&1; then
      echo "✅ 编译器可以正常运行"
      "$CLANG_BIN" --version | head -1
    else
      echo "❌ 编译器无法运行"
      echo "   当前系统架构: $SYSTEM_ARCH"
      echo "   编译器架构: $COMPILER_ARCH"
      echo "   错误信息:"
      "$CLANG_BIN" --version 2>&1 | head -3 || true
    fi
  else
    echo "⚠️  无法确定 CLANG 的格式: $(file "$CLANG_BIN")"
    echo ""
    echo "尝试直接运行测试："
    if "$CLANG_BIN" --version >/dev/null 2>&1; then
      echo "✅ 编译器可以运行"
      "$CLANG_BIN" --version | head -1
    else
      echo "❌ 编译器无法运行"
      echo "   错误信息:"
      "$CLANG_BIN" --version 2>&1 | head -3 || true
    fi
  fi
else
  echo "❌ CLANG binary 不存在"
fi
