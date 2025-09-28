# QEMU构建调试指南

## 问题诊断

当你遇到QEMU构建错误时，可以按照以下步骤进行调试：

### 1. 本地调试

#### 步骤1：检查系统依赖
```bash
# 运行本地构建测试
./scripts/build-local-test.sh
```

这个脚本会：
- 检查系统依赖（gcc, g++, make, pkg-config）
- 检查可选依赖（glib, pixman, openssl）
- 尝试构建QEMU（不依赖HarmonyOS SDK）
- 测试共享库创建

#### 步骤2：调试SDK路径
```bash
# 运行SDK路径调试脚本
./scripts/debug-sdk-paths.sh
```

这个脚本会：
- 检查SDK根目录是否存在
- 搜索常见的NDK路径
- 查找clang编译器
- 验证NDK结构
- 提供环境变量设置建议

### 2. 云端调试

#### 使用GitHub Actions调试
1. 在GitHub Actions页面手动触发 `debug-sdk-only` workflow
2. 查看详细的SDK下载和解压过程
3. 检查SDK结构分析结果
4. 下载调试结果artifact

### 3. 常见问题解决

#### 问题1：`dirname: missing operand`
**原因**：`find`命令没有找到目标文件，导致`dirname`没有参数

**解决方案**：
1. 运行 `./scripts/debug-sdk-paths.sh` 检查SDK安装
2. 确认SDK是否正确下载和解压
3. 检查SDK路径是否正确

#### 问题2：`Could not find HarmonyOS NDK`
**原因**：SDK结构不符合预期

**解决方案**：
1. 检查SDK下载是否完整
2. 确认SDK版本兼容性
3. 手动设置环境变量

#### 问题3：`CC not found`
**原因**：编译器路径不正确

**解决方案**：
1. 运行调试脚本找到正确的编译器路径
2. 手动设置环境变量：
```bash
export OHOS_NDK_HOME="/path/to/native"
export SYSROOT="$OHOS_NDK_HOME/sysroot"
export CC="$OHOS_NDK_HOME/llvm/bin/aarch64-unknown-linux-ohos-clang"
```

### 4. 手动设置环境变量

如果自动检测失败，可以手动设置：

```bash
# 设置SDK路径
export OHOS_NDK_HOME="/opt/harmonyos-sdk/sdk/default/openharmony/native"
export SYSROOT="$OHOS_NDK_HOME/sysroot"

# 设置编译器
export CC="$OHOS_NDK_HOME/llvm/bin/aarch64-unknown-linux-ohos-clang"
export CXX="$OHOS_NDK_HOME/llvm/bin/aarch64-unknown-linux-ohos-clang++"
export AR="$OHOS_NDK_HOME/llvm/bin/llvm-ar"
export STRIP="$OHOS_NDK_HOME/llvm/bin/llvm-strip"
export RANLIB="$OHOS_NDK_HOME/llvm/bin/llvm-ranlib"
export LD="$OHOS_NDK_HOME/llvm/bin/ld.lld"

# 验证设置
echo "CC: $CC"
echo "CXX: $CXX"
echo "SYSROOT: $SYSROOT"

# 测试编译器
$CC --version
```

### 5. 调试脚本说明

#### `debug-sdk-paths.sh`
- **用途**：调试HarmonyOS SDK安装和路径
- **功能**：
  - 检查SDK根目录
  - 搜索NDK结构
  - 查找编译器
  - 验证sysroot
  - 提供环境变量建议

#### `build-local-test.sh`
- **用途**：测试QEMU构建（不依赖HarmonyOS SDK）
- **功能**：
  - 检查系统依赖
  - 构建QEMU静态库
  - 测试共享库创建
  - 验证构建结果

#### `build-qemu-simple.sh`
- **用途**：简化的HarmonyOS QEMU构建
- **功能**：
  - 自动检测SDK路径
  - 构建QEMU和NAPI模块
  - 创建共享库
  - 复制到目标目录

### 6. 调试流程

#### 标准调试流程：
1. **本地测试**：运行 `./scripts/build-local-test.sh`
2. **SDK调试**：运行 `./scripts/debug-sdk-paths.sh`
3. **手动设置**：根据调试结果手动设置环境变量
4. **重新构建**：运行 `./scripts/build-qemu-simple.sh`

#### 云端调试流程：
1. **触发workflow**：手动触发 `debug-sdk-only` workflow
2. **查看日志**：检查SDK下载和解压过程
3. **下载结果**：下载调试结果artifact
4. **分析问题**：根据日志和结果分析问题

### 7. 环境要求

#### 本地环境：
- macOS: Xcode Command Line Tools
- Ubuntu: build-essential, pkg-config
- 可选: glib, pixman, openssl

#### 云端环境：
- Ubuntu 22.04 LTS
- 自动安装依赖
- HarmonyOS SDK 6.0.0.848

### 8. 故障排除

#### 如果所有调试都失败：
1. 检查网络连接（SDK下载）
2. 确认SDK版本兼容性
3. 尝试不同的SDK版本
4. 使用系统包管理器安装依赖

#### 如果构建成功但运行时失败：
1. 检查库文件路径
2. 验证权限设置
3. 检查设备兼容性
4. 查看运行时日志

---

**记住**：调试是一个迭代过程，逐步排除问题，最终找到解决方案！ 🔍✨
