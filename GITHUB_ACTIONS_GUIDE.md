# GitHub Actions 构建指南

## 问题解决

### 原始问题
1. **Git子模块错误**: `No url found for submodule path 'third_party/deps/glib/src' in .gitmodules`
2. **SDK下载错误**: `mv: cannot stat 'commandline-tools': No such file or directory`

### 解决方案

#### 1. 子模块问题修复
- 将所有workflow中的 `submodules: recursive` 改为 `submodules: false`
- 避免初始化有问题的第三方依赖子模块
- 使用系统包管理器安装依赖库

#### 2. SDK下载问题修复
- 动态检测解压后的目录结构
- 支持多种可能的SDK目录布局
- 自动查找正确的工具路径

## 可用的Workflow

### 1. 调试SDK下载 (`debug-sdk.yml`)
**用途**: 专门用于调试SDK下载和解压问题

**触发方式**: 手动触发 (workflow_dispatch)

**功能**:
- 下载HarmonyOS SDK
- 分析解压后的目录结构
- 测试工具安装和路径发现
- 生成详细的调试信息

**使用方法**:
```bash
# 在GitHub Actions页面手动触发
# 查看详细的SDK结构分析
```

### 2. 简化构建 (`build-simple.yml`)
**用途**: 推荐使用的稳定构建流程

**触发方式**: 
- 推送到 `main` 或 `develop` 分支
- Pull Request到 `main` 分支
- 手动触发

**功能**:
- 使用简化的QEMU构建配置
- 最小化依赖，避免有问题的子模块
- 动态SDK路径发现
- 生成基本的NAPI模块

### 3. 完整构建 (`build-qemu-harmonyos.yml`)
**用途**: 包含所有功能的完整构建

**触发方式**: 同简化构建

**功能**:
- 完整的QEMU功能构建
- 包含VNC、RDP等高级功能
- 更复杂的依赖管理

### 4. 快速构建 (`quick-build.yml`)
**用途**: 快速测试构建流程

**触发方式**: 手动触发

**功能**:
- 最小化的构建步骤
- 快速验证构建环境

## 使用建议

### 首次使用
1. **先运行调试workflow**:
   ```bash
   # 在GitHub Actions页面手动触发 debug-sdk.yml
   # 查看SDK下载和安装是否正常
   ```

2. **然后运行简化构建**:
   ```bash
   # 手动触发 build-simple.yml
   # 验证基本构建流程
   ```

3. **最后运行完整构建**:
   ```bash
   # 如果简化构建成功，再尝试完整构建
   ```

### 日常开发
- 使用 `build-simple.yml` 进行常规构建
- 只有在需要完整功能时才使用 `build-qemu-harmonyos.yml`

## 构建产物

构建成功后会生成以下文件：

```
entry/src/main/libs/arm64-v8a/
├── libqemu_full.so      # QEMU完整功能库
└── libqemu_hmos.so      # NAPI模块

entry/src/main/oh_modules/
└── libqemu_full.so      # 运行时加载的QEMU库
```

## 故障排除

### 常见问题

1. **SDK下载失败**
   - 检查网络连接
   - 验证下载链接是否有效
   - 查看GitHub Actions日志

2. **构建失败**
   - 先运行 `debug-sdk.yml` 检查SDK安装
   - 查看构建日志中的具体错误
   - 尝试使用简化构建

3. **库文件缺失**
   - 确认所有构建步骤都成功
   - 检查artifact下载
   - 验证文件复制路径

### 调试步骤

1. **查看构建日志**:
   ```bash
   # 在GitHub Actions页面查看详细日志
   ```

2. **验证SDK安装**:
   ```bash
   # 运行 debug-sdk.yml 查看SDK结构
   ```

3. **测试工具可用性**:
   ```bash
   # 在构建日志中查找工具路径验证
   ```

## 环境要求

- **运行环境**: Ubuntu 22.04 LTS
- **SDK版本**: HarmonyOS 6.0.0.848
- **目标架构**: aarch64-linux-ohos
- **构建工具**: CMake, Ninja, Meson

## 性能优化

- 使用多核并行编译
- 缓存构建依赖
- 增量构建支持
- 优化库文件大小

---

**注意**: 如果遇到问题，请先运行 `debug-sdk.yml` 获取详细的调试信息，然后根据结果调整构建配置。
