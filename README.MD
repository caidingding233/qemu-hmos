# QEMU for HarmonyOS (HMOS)
你能跑的，**超乎你的想象**！

###### *打造鸿蒙版的 UTM 为本项目建设目标*

在 **HarmonyOS NEXT**（鸿蒙平板 / 鸿蒙电脑）上以 **App 形态运行 QEMU**，让设备拥有本地虚拟机能力，运行 Windows / Linux 来宾系统。
项目面向 **个人自用 / 实验 / 开发者**：无需 root、不需破解、不依赖 HNP；QEMU 嵌入为 .so 库，默认使用 TCG JIT，并尝试探测 KVM 加速。

> ⚠️ 小字说明：本项目尚处于实验阶段，部分功能未完善。请仅在合法镜像 & 自测环境下使用。大字与小字之间的鸿蒙差距，正是我们拼命填上的距离。
>
> 免责声明：请仅在拥有合法授权的镜像/系统上使用。本项目仅作研究与个人测试，不建议对外分发。本项目不提供任何形式的技术支持，也不负责任何形式的损失或伤害。本项目的作者不承担任何因使用本项目而导致的任何损失或伤害。
>
> QEMU专指Quick Emulator模拟器 感谢QEMU的开发者帮助打造上游生态!
---

## ✨ 核心特性（已实现 / 规划中）

- 在 MatePad / 鸿蒙电脑上运行 Windows 11 ARM、Linux ARM64（来宾系统）
- 离线可访问：通过 hostfwd 实现宿主到来宾端口映射（默认 RDP / VNC 转发）
- 安装期使用 VNC 界面，运行期通过 RDP 嵌入视图交互
- 支持 *StartProgram*：点击鸿蒙图标即拉起特定 EXE 应用
- 文件共享：RDP 驱动器重定向，将 App 沙箱目录映射为来宾盘符
- 媒体控制透传、快照 / 恢复、RemoteApp / RAIL、virtiofs / 9p / Samba 等功能在规划中
- 探测 / 降级机制：若 `/dev/kvm` 不可用，自动降级为 TCG 模式

> ⚠️ 注意事项与风险
> • 若设备 / 宿主系统不暴露 `/dev/kvm`，加速不可用 → 性能退回模拟模式
> • JIT 模式可能会受到签名 / 权限限制
> • 图形、USB、音频、GPU 虚拟支持尚未稳定
> • 建议先在老版本 / 已知兼容设备上尝试，不建议直接用于生产环境

---

## 📦 环境与前置条件

- DevEco Studio 5+，HarmonyOS NEXT SDK（API 12+）
- 开发者证书 + 调试签名，用于启用 JIT / 可执行内存
- 目标设备：HarmonyOS NEXT 平板或电脑（开启开发者选项）
- 构建依赖（本机）：cmake / meson / ninja / C/C++ toolchain
- 提供 Host 构建 action 检查（Ubuntu Runner 编译脚本）

- 没有安装 HarmonyOS NDK? CMake 会自动回退到**主机侧简化 NAPI shim**，在 GitHub Actions 等 CI 环境中也能完成编译检查。

> 📦 仓库自带 `Native Build (Host)` workflow：在 Ubuntu runner 上执行 `cmake -S entry/src/main/cpp -B build/host && cmake --build build/host`，用于验证原生代码是否能通过基础编译。


## 🚀 快速上手指南

```bash
git clone https://github.com/caidingding233/qemu-hmos.git
cd qemu-hmos
# 配置签名 / 证书
# 编译 libqemu_full.so
./configure --target-list=aarch64-softmmu --enable-tcg …
make -j
# 放置 so 文件到 app/libs/arm64-v8a/
# 打包 hap / 部署到设备

在 App 中：
	1.	新建 VM，选定来宾系统（Windows / Linux）
	2.	下载 / 准备 ISO / 镜像
	3.	启动安装（使用 VNC）
	4.	安装完成后使用 RDP 进入、体验系统

⸻

⚠️ 注意事项与风险
	•	若设备 / 宿主系统不暴露 /dev/kvm，加速不可用 → 性能退回模拟模式
	•	JIT 模式可能会受到签名 / 权限限制
	•	图形、USB、音频、GPU 虚拟支持尚未稳定
	•	建议先在老版本 / 已知兼容设备上尝试，不建议直接用于生产环境

⸻

📅 路线图 & 规划

版本 / 阶段	功能重点
MVP	QEMU 嵌入 + VNC / RDP 启动 + StartProgram + 文件映射
V1	媒体透传 + 快照 / 恢复 + UI 优化
V2+	RemoteApp / RAIL + GPU 加速 + USB / virtiofs 支持 + 多系统模板


## 🧩 贡献指南

欢迎提交 Issue / PR，尤其是：
	•	UI / 前端交互优化
	•	虚拟机稳定性增强 / bug 修复
	•	新系统镜像支持 / Guest OS 模板
	•	媒体 / 图形 / 外设适配 / 驱动补全
	•	文档 / 教程 / 示例镜像

让我们一起把鸿蒙虚拟机做成社区的自豪！

---

## 🏗️ 架构简述

```
app/
  entry/ArkTS UI（虚拟机 / Apps / 我的）
  native/ NAPI 桥（startVm/stopVm 等）
  libs/arm64-v8a/libqemu.so        ← 内嵌的 QEMU（aarch64-softmmu）
  assets/QEMU_EFI.fd               ← EDK2 固件
  assets/tools/                    ← 首启脚本、驱动等（可选）
```

- **QEMU 作为库**：导出 `libqemu_full(argc, argv)`；App 内以线程方式启动主循环
- **显示**：安装期 `-display vnc=:1`；日常嵌入 RDP 视图连接 `127.0.0.1:3390`
- **网络**：user-net + `hostfwd`（离线也可用）
- **KVM/JIT**：运行时 `open("/dev/kvm") + KVM_GET_API_VERSION` 探测；前置调用 `prctl("jit",1)`（开发签名下）

---

## 🚀 快速开始

1. **克隆仓库**
   ```bash
   git clone https://github.com/caidingding233/qemu-hmos.git
   ```
2. **配置签名**
   - 在 DevEco Studio 中为本 App 配置 **开发者证书 + 调试签名**（用于 JIT）
3. **编译 QEMU 为库**
   - 建议目标：`aarch64-softmmu`；可选开启 TCI 兜底（无 JIT 时仍可运行但性能较低）
   - 典型（示例）：
     ```bash
     ./configure --target-list=aarch64-softmmu \
                 --enable-tcg --disable-debug-info \
                 --disable-modules
     make -j$(nproc)
     # 产出 libqemu_full.so（或将 qemu-system-aarch64 的入口重命名为 libqemu_full 并链接为 .so）
     ```
   - 或者是在Release界面下载我上传的预编译好的so库
   - 将产物放入：`app/entry/libs/arm64-v8a/libqemu_full.so`
4. **准备固件与资源**
   - 推荐将 `edk2-aarch64-code.fd`（EDK2 固件）放入 `app/entry/src/main/resources/rawfile/`（或 assets）；若暂时缺失，App 会自动跳过 `-bios` 参数并让 QEMU 使用内置缺省固件，方便快速验证能否起机
5. **运行到设备**
   - 连接鸿蒙设备（平板/电脑），运行工程

---

## 🖥️ 创建与安装来宾系统

1. 在 App 的 **虚拟机** 页创建 VM：选择 Windows 11 ARM 或 Linux ARM64
2. 选择/下载 ISO（支持断点续传与 SHA 校验）
3. 创建磁盘（比如 `win11arm.qcow2`，默认 64 GB）
4. 启动安装（安装期使用 VNC 观察）
5. 安装完成后，App 将改用 RDP 连接 `127.0.0.1:3390` 进入系统

> 典型 QEMU 参数（由 App 生成）：
```text
-machine virt,gic-version=3,virtualization=on
-cpu max -smp 4 -m 6144
-accel tcg,thread=multi,tb-size=128
-bios edk2-aarch64-code.fd（若未提供固件，运行时将省略该参数）
-drive if=none,id=d0,file=win11arm.qcow2,format=qcow2,cache=writeback,aio=threads,discard=unmap
-device nvme,drive=d0,serial=nvme0
-netdev user,id=n0,hostfwd=tcp:127.0.0.1:3390-:3389
-device virtio-net-pci,netdev=n0
```

---

## 🧰 首启增强（可选，一键配置）

- 启用 RDP、放通防火墙
- 安装 VirtIO等虚拟机用到的驱动、魔改版的QEMU Guest Agent（Windows）、小白调试助手（用于固定虚拟机内Apps到鸿蒙的桌面）、鸿蒙工具链等等
- 将 App 沙箱目录映射为 `Z:`（RDP 驱动器重定向）
- （WIP）媒体桥（GSMTC）自启，支持播放状态透传

---

## 📱 Apps 启动与桌面集成

- **StartProgram**：在 **Apps** 页为某个 Windows 程序创建入口 → 点击即连接并拉起指定 EXE  
- **桌面图标**
  - 鸿蒙电脑：若系统允许**读写桌面目录**，可编程写入快捷方式文件
  - 平板：使用**静态快捷方式/服务卡片**，用户“固定到桌面”

---

## 🩺 故障排查（FAQ）

- **找不到 `/dev/kvm` / 无法打开**  
  这是预期：容器通常不暴露 KVM。项目会自动降级到 `tcg`。  
- **JIT 打不开**  
  确认使用开发者证书 + 调试签名；若仍失败，TCI 仍可运行但性能有限。  
- **RDP 连接不上**  
  确认 VM 内已启用远程桌面；端口映射为 `hostfwd tcp:127.0.0.1:3390-:3389`；安装期可先用 VNC。  
- **文件互通**  
  优先使用 RDP 驱动器重定向；长期建议切 virtiofs/9p（WIP）。

---

## 🗺️ Roadmap（摘录）

- MVP：QEMU 内嵌（TCG + JIT）、VNC 安装 + RDP 使用、Apps StartProgram、RDP 驱动器重定向
- V1：媒体控制透传（DVC + GSMTC + AVSession）、快照/休眠/恢复、下载器可视化
- V2：RemoteApp/RAIL、virtiofs/9p/Samba、图形与输入高级适配、多系统模板

---

---

## 📜 许可证

详见仓库内 LICENSE 文件