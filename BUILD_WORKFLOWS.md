# QEMU-HMOS 构建工作流

本项目使用三个分离的 GitHub Actions 工作流来构建不同的组件：

## 1. Build QEMU SO for HarmonyOS (`build-robust.yml`)

**用途**：构建 QEMU 虚拟机核心 SO 文件

**触发条件**：
- 手动触发 (`workflow_dispatch`)
- 推送到 main 分支 (`push`)

**输出**：
- `qemu-system-aarch64` - ARM64 架构 QEMU
- `qemu-system-x86_64` - x86_64 架构 QEMU
- `qemu-system-i386` - i386 架构 QEMU
- `libqemu_full.so` - HarmonyOS 应用使用的 QEMU SO 文件

**构建环境**：
- Ubuntu 24.04
- HarmonyOS NDK (交叉编译)
- ARM64 开发库 (glib, pixman, etc.)

## 2. Build HAP for HarmonyOS (`build-hap.yml`)

**用途**：构建 HarmonyOS 应用安装包 (HAP)

**触发条件**：
- 手动触发 (`workflow_dispatch`)
- QEMU SO 构建完成后自动触发 (`workflow_run`)

**输出**：
- `*.hap` - HarmonyOS 应用安装包

**安装方式**：
通过小白调试助手 App 安装到 HarmonyOS 设备

**构建环境**：
- Ubuntu 24.04
- HarmonyOS SDK
- Node.js + hvigor

## 3. Build Guest Tools (`build-guest-tools.yml`)

**用途**：构建虚拟机客户机工具

**触发条件**：
- 手动触发 (`workflow_dispatch`)
- 推送到 main 分支 (`push`)

**输出**：
- Linux guest tools: `.deb`, `.rpm`
- Windows guest tools: `.exe`, `.msi`
- macOS guest tools: `.pkg`, `.dmg`

**构建环境**：
- Linux: Ubuntu 24.04 + GCC
- Windows: Ubuntu 24.04 + MinGW
- macOS: macOS-latest + Homebrew

## 构建流程

```
QEMU SO 构建 → HAP 构建 → 部署到设备
    ↓
Guest Tools 构建 → 分发给虚拟机客户机
```

## 手动触发

可以使用 GitHub Actions 界面手动触发各个工作流：

1. 进入项目的 Actions 标签页
2. 选择对应的 workflow
3. 点击 "Run workflow" 按钮

## 注意事项

- SO 构建完成后会自动触发 HAP 构建
- Guest tools 构建独立运行，不依赖其他构建
- 所有构建产物都作为 GitHub Artifacts 保存，可下载使用
