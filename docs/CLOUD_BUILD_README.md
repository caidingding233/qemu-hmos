# QEMU HarmonyOS 云端构建指南

## 概述

这个项目使用GitHub Actions在云端构建QEMU for HarmonyOS，避免了本地编译环境的复杂性。

## 构建流程

### 1. 自动触发

构建会在以下情况下自动触发：
- 推送到 `main` 或 `develop` 分支
- 创建Pull Request到 `main` 分支
- 手动触发（workflow_dispatch）

### 2. 构建步骤

#### 环境准备
- Ubuntu 22.04 LTS
- 安装必要的构建工具（gcc, cmake, ninja等）
- 下载HarmonyOS SDK 6.0.0.848

#### QEMU编译
- 配置交叉编译环境
- 编译QEMU静态库：
  - `libqemu-aarch64-softmmu.a` - 主要QEMU库
  - `libqemuutil.a` - QEMU工具库
  - `libfdt.a` - 设备树库
  - `libsoftfloat.a` - 软浮点库

#### 共享库创建
- 将静态库链接成 `libqemu_full.so`
- 剥离调试符号以减小文件大小

#### NAPI模块编译
- 使用HarmonyOS NDK编译NAPI模块
- 生成 `libqemu_hmos.so`

### 3. 输出文件

构建完成后会生成以下文件：

```
entry/src/main/libs/arm64-v8a/
├── libqemu_full.so      # QEMU完整功能库
└── libqemu_hmos.so      # NAPI模块

entry/src/main/oh_modules/
└── libqemu_full.so      # 运行时加载的QEMU库
```

## 使用方法

### 1. 查看构建状态

1. 访问GitHub仓库的Actions页面
2. 查看最新的构建状态
3. 如果构建失败，查看日志找出问题

### 2. 下载构建产物

构建成功后会生成artifact：
- `qemu-harmonyos-libraries` - 包含所有编译好的库文件

### 3. 本地使用

1. 下载artifact并解压
2. 将库文件复制到项目对应位置
3. 重新构建HarmonyOS应用

## 构建配置

### 环境变量

```bash
OHOS_NDK_HOME="/opt/harmonyos-sdk/sdk/default/openharmony/native"
SYSROOT="${OHOS_NDK_HOME}/sysroot"
CC="${OHOS_NDK_HOME}/llvm/bin/aarch64-unknown-linux-ohos-clang"
CXX="${OHOS_NDK_HOME}/llvm/bin/aarch64-unknown-linux-ohos-clang++"
```

### QEMU配置选项

```bash
--target-list=aarch64-softmmu
--cross-prefix=aarch64-unknown-linux-ohos-
--enable-tcg
--enable-fdt=internal
--disable-kvm
--disable-xen
```

## 故障排除

### 常见问题

1. **SDK下载失败**
   - 检查下载链接是否有效
   - 确认网络连接正常

2. **编译失败**
   - 查看构建日志
   - 检查依赖库是否完整

3. **库文件缺失**
   - 确认所有构建步骤都成功
   - 检查文件复制路径

### 调试方法

1. **查看构建日志**
   ```bash
   # 在GitHub Actions中查看详细日志
   ```

2. **验证库文件**
   ```bash
   file libqemu_full.so
   nm -D libqemu_hmos.so | grep napi
   ```

3. **检查符号**
   ```bash
   objdump -T libqemu_full.so | head -20
   ```

## 性能优化

### 构建优化
- 使用多核并行编译
- 缓存依赖库
- 增量构建支持

### 库文件优化
- 剥离调试符号
- 使用LTO优化
- 压缩库文件

## 维护说明

### 定期更新
- 监控QEMU版本更新
- 更新HarmonyOS SDK版本
- 测试新版本兼容性

### 版本管理
- 为每个构建打标签
- 保留历史构建产物
- 文档化版本变更

## 联系支持

如果遇到问题，请：
1. 查看GitHub Issues
2. 提交新的Issue
3. 提供详细的错误日志

---

**注意**: 这个构建流程专门为HarmonyOS NEXT设计，确保生成的库文件与目标平台兼容。
