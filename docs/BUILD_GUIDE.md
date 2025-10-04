# QEMU-HMOS 构建指南

## 概述

QEMU-HMOS项目需要在Linux环境下使用HarmonyOS NDK进行交叉编译。本文档提供了详细的构建步骤和故障排除指南。

## 环境要求

### 硬件要求
- **Linux机器**：Ubuntu 20.04+ 或 CentOS 8+（推荐Ubuntu 22.04）
- **内存**：至少16GB RAM（构建QEMU需要大量内存）
- **存储**：至少50GB可用空间
- **CPU**：多核处理器（构建过程可以并行）

### 软件依赖
- **HarmonyOS NEXT SDK**：API 12+
- **DevEco Studio**：最新版本
- **鸿蒙工具链**：包括hvigor、hdc等
- **交叉编译工具链**：OpenHarmony NDK

## 快速开始

### 1. 使用GitHub Actions（推荐）

最简单的方式是使用GitHub Actions进行云端构建：

1. 推送代码到GitHub
2. 在Actions页面选择"Build QEMU-HMOS (Simplified)"
3. 点击"Run workflow"
4. 等待构建完成，下载artifacts

### 2. 本地构建

#### 步骤1：安装HarmonyOS NDK

```bash
# 下载HarmonyOS NDK
wget https://repo.huaweicloud.com/openharmony/os/5.1.0-Release/ohos-sdk-windows_linux-public.tar.gz

# 解压
tar -xzf ohos-sdk-windows_linux-public.tar.gz

# 查找native SDK
cd ohos-sdk/linux
NATIVE_ZIP=$(find . -name "*native*.zip" | head -1)
unzip "$NATIVE_ZIP"

# 设置环境变量
export OHOS_NDK_HOME="$(pwd)/$(find . -name "*native*" -type d | head -1)"
export SYSROOT="$OHOS_NDK_HOME/sysroot"
export CC="$OHOS_NDK_HOME/llvm/bin/clang"
export CXX="$OHOS_NDK_HOME/llvm/bin/clang++"
```

#### 步骤2：安装系统依赖

```bash
sudo apt-get update
sudo apt-get install -y build-essential cmake curl wget unzip python3 \
                      libglib2.0-dev libpixman-1-dev libssl-dev \
                      libcurl4-openssl-dev libssh-dev libgnutls28-dev \
                      libsasl2-dev libpam0g-dev libbz2-dev libzstd-dev \
                      libpcre2-dev pkg-config meson tree \
                      binutils-aarch64-linux-gnu gcc-aarch64-linux-gnu \
                      libc6-dev libc6-dev-arm64-cross
```

#### 步骤3：运行构建脚本

```bash
# 使用修复版构建脚本
chmod +x tools/build-fixed.sh
./tools/build-fixed.sh
```

## 构建过程详解

### QEMU构建

1. **配置阶段**：
   - 使用HarmonyOS NDK的clang编译器
   - 设置正确的target和sysroot
   - 禁用不兼容的功能（KVM、Xen等）
   - 启用必要功能（TCG、VNC、RDP等）

2. **编译阶段**：
   - 修复posix_memalign兼容性问题
   - 使用静态链接避免依赖问题
   - 生成libqemu_full.so共享库

### NAPI模块构建

1. **CMake配置**：
   - 设置交叉编译环境
   - 链接QEMU库
   - 配置HarmonyOS特定的编译选项

2. **编译**：
   - 生成libqemu_hmos.so
   - 包含所有NAPI接口

## 常见问题解决

### 1. SDK下载失败

**问题**：无法下载HarmonyOS NDK

**解决方案**：
```bash
# 尝试多个下载源
NDK_URLS=(
  "https://repo.huaweicloud.com/openharmony/os/5.1.0-Release/ohos-sdk-windows_linux-public.tar.gz"
  "https://repo.huaweicloud.com/openharmony/os/5.0.0-Release/ohos-sdk-windows_linux-public.tar.gz"
  "https://repo.huaweicloud.com/openharmony/os/4.1.0-Release/ohos-sdk-windows_linux-public.tar.gz"
)

for url in "${NDK_URLS[@]}"; do
  if wget "$url"; then
    echo "下载成功: $url"
    break
  fi
done
```

### 2. 编译器路径问题

**问题**：找不到clang编译器

**解决方案**：
```bash
# 查找编译器
find $OHOS_NDK_HOME -name "*clang*" -type f

# 设置正确的路径
export CC="$OHOS_NDK_HOME/llvm/bin/clang"
export CXX="$OHOS_NDK_HOME/llvm/bin/clang++"
```

### 3. posix_memalign错误

**问题**：HarmonyOS musl libc的posix_memalign兼容性问题

**解决方案**：
```bash
# 创建修复头文件
cat > posix_memalign_fix.h << 'EOF'
#ifndef POSIX_MEMALIGN_FIX_H
#define POSIX_MEMALIGN_FIX_H
#include <stdlib.h>
#include <errno.h>
#include <stdint.h>

static inline int posix_memalign_fixed(void **memptr, size_t alignment, size_t size) {
    if (alignment < sizeof(void*) || (alignment & (alignment - 1)) != 0) {
        return EINVAL;
    }
    void *ptr = aligned_alloc(alignment, size);
    if (ptr) {
        *memptr = ptr;
        return 0;
    }
    ptr = malloc(size + alignment - 1);
    if (!ptr) return ENOMEM;
    uintptr_t addr = (uintptr_t)ptr;
    uintptr_t aligned = (addr + alignment - 1) & ~(alignment - 1);
    *memptr = (void*)aligned;
    return 0;
}

#ifndef posix_memalign
#define posix_memalign posix_memalign_fixed
#endif
#endif
EOF

# 在编译时包含此头文件
export CFLAGS="-include posix_memalign_fix.h $CFLAGS"
```

### 4. 依赖库问题

**问题**：gnutls等依赖库交叉编译失败

**解决方案**：
```bash
# 禁用有问题的依赖
../configure \
  --disable-gnutls \
  --disable-nettle \
  --disable-gcrypt \
  --disable-libssh \
  # ... 其他选项
```

### 5. 内存不足

**问题**：构建过程中内存不足

**解决方案**：
```bash
# 减少并行编译数量
make -j2  # 而不是 make -j$(nproc)

# 或者增加交换空间
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

## 构建产物

构建成功后，会生成以下文件：

- `third_party/qemu/build/qemu-system-aarch64` - QEMU主程序
- `third_party/qemu/build/libqemu_full.so` - QEMU共享库
- `entry/src/main/cpp/build/libqemu_hmos.so` - NAPI模块

## 部署到设备

1. **复制库文件**：
```bash
# 复制到正确位置
cp third_party/qemu/build/libqemu_full.so entry/src/main/cpp/libs/arm64-v8a/
cp entry/src/main/cpp/build/libqemu_hmos.so entry/src/main/cpp/libs/arm64-v8a/
```

2. **构建HAP包**：
```bash
./hvigorw assembleHap
```

3. **安装到设备**：
```bash
hdc install -r entry/build/outputs/hap/*.hap
```

## 调试

### 查看构建日志

```bash
# 启用详细日志
export CONFIGURE_DEBUG=1
export V=1

# 查看config.log
cat third_party/qemu/build/config.log
```

### 验证构建结果

```bash
# 检查文件类型
file third_party/qemu/build/qemu-system-aarch64
file entry/src/main/cpp/build/libqemu_hmos.so

# 检查依赖
ldd third_party/qemu/build/qemu-system-aarch64
```

## 性能优化

1. **使用SSD**：将源码和构建目录放在SSD上
2. **增加内存**：至少16GB RAM
3. **并行编译**：使用`make -j$(nproc)`
4. **ccache**：使用编译器缓存加速重复构建

```bash
# 安装ccache
sudo apt-get install ccache

# 配置ccache
export CC="ccache $CC"
export CXX="ccache $CXX"
```

## 故障排除

如果遇到问题，请按以下步骤排查：

1. 检查环境变量是否正确设置
2. 查看构建日志中的错误信息
3. 确认所有依赖库已正确安装
4. 检查磁盘空间是否充足
5. 验证HarmonyOS NDK版本是否兼容

## 联系支持

如果问题仍然存在，请：

1. 查看GitHub Issues
2. 提供完整的构建日志
3. 说明使用的操作系统和NDK版本
4. 提供错误信息截图
