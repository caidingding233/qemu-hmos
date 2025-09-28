#!/bin/bash
set -euo pipefail

echo "=== Mac本地QEMU构建脚本 ==="
echo "这个脚本在Mac上构建QEMU，不依赖HarmonyOS SDK"
echo ""

# 检查是否在Mac上
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "❌ 这个脚本只能在Mac上运行"
    exit 1
fi

echo "✅ 检测到Mac系统"
echo ""

# 检查是否在正确的目录
if [ ! -d "third_party/qemu" ]; then
    echo "❌ 错误：请从项目根目录运行此脚本"
    exit 1
fi

echo "=== 检查系统依赖 ==="
MISSING_DEPS=()

# 检查Xcode Command Line Tools
if ! command -v gcc &> /dev/null; then
    MISSING_DEPS+=("Xcode Command Line Tools")
fi

if ! command -v make &> /dev/null; then
    MISSING_DEPS+=("make")
fi

if ! command -v pkg-config &> /dev/null; then
    MISSING_DEPS+=("pkg-config")
fi

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo "❌ 缺少依赖: ${MISSING_DEPS[*]}"
    echo "请安装："
    echo "  xcode-select --install  # 安装Xcode Command Line Tools"
    echo "  brew install pkg-config  # 安装pkg-config"
    exit 1
fi

echo "✅ 所有系统依赖已安装"
echo ""

# 检查可选依赖
echo "=== 检查可选依赖 ==="
OPTIONAL_DEPS=("glib-2.0" "pixman-1" "openssl")

for dep in "${OPTIONAL_DEPS[@]}"; do
    if pkg-config --exists "$dep" 2>/dev/null; then
        echo "✅ $dep: $(pkg-config --modversion "$dep")"
    else
        echo "⚠️  $dep: 未找到 (将通过brew安装)"
        case $dep in
            "glib-2.0")
                echo "  运行: brew install glib"
                ;;
            "pixman-1")
                echo "  运行: brew install pixman"
                ;;
            "openssl")
                echo "  运行: brew install openssl"
                ;;
        esac
    fi
done
echo ""

# 准备QEMU构建
echo "=== 准备QEMU构建 ==="
cd third_party/qemu

# 清理之前的构建
echo "清理之前的构建..."
rm -rf build_mac_local
mkdir -p build_mac_local
cd build_mac_local

# 配置QEMU
echo "配置QEMU..."
../configure \
  --target-list=aarch64-softmmu \
  --enable-tcg \
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
  --disable-fdt

# 构建QEMU
echo "构建QEMU..."
make -j$(sysctl -n hw.ncpu)

# 验证构建结果
echo "=== 构建验证 ==="
if [ ! -f "libqemu-aarch64-softmmu.a" ]; then
    echo "❌ 错误：libqemu-aarch64-softmmu.a 未找到"
    exit 1
fi

if [ ! -f "libqemuutil.a" ]; then
    echo "❌ 错误：libqemuutil.a 未找到"
    exit 1
fi

echo "✅ QEMU构建成功"
echo ""

# 显示构建结果
echo "=== 构建结果 ==="
echo "生成的库文件："
ls -la *.a
echo ""
echo "库文件大小："
du -h *.a
echo ""

# 测试创建共享库
echo "=== 测试共享库创建 ==="
echo "创建测试共享库..."
g++ -shared -fPIC -Wl,--no-undefined \
  -Wl,--whole-archive \
  libqemu-aarch64-softmmu.a \
  libqemuutil.a \
  -Wl,--no-whole-archive \
  -lpthread -ldl -lm -lz \
  -o libqemu_test.dylib

if [ -f "libqemu_test.dylib" ]; then
    echo "✅ 测试共享库创建成功"
    echo "大小: $(du -h libqemu_test.dylib | cut -f1)"
    echo "类型: $(file libqemu_test.dylib)"
else
    echo "❌ 创建测试共享库失败"
fi

echo ""
echo "🎉 Mac本地构建测试完成！"
echo ""
echo "注意："
echo "1. 这是Mac上的本地构建，不包含HarmonyOS特定的功能"
echo "2. 生成的库文件是Mac格式(.dylib)，不能直接在HarmonyOS上使用"
echo "3. 要构建HarmonyOS版本，需要安装HarmonyOS SDK"
echo ""
echo "下一步："
echo "1. 如果要构建HarmonyOS版本，请先安装HarmonyOS SDK"
echo "2. 或者使用GitHub Actions进行云端构建"
echo "3. 或者修改脚本以支持交叉编译到HarmonyOS"
