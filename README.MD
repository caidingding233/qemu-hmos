# QEMU for HarmonyOS (HMOS)  
## 你能跑的，**超乎你的想象**！

###### *打造鸿蒙版的 UTM 为本项目建设目标*

在 **HarmonyOS NEXT**（鸿蒙平板 / 鸿蒙电脑）上以 **App 形态** 启动 QEMU，让设备拥有真正的虚拟机能力，运行 Windows / Linux 来宾系统。  
本项目面向 **个体玩家 / 实验探索者 / 技术控**：**无需 root、不挖坑、不靠破解、不依赖 HNP**，技术路线透明公开。  

> ⚠️ **小字说明**：本项目尚处于实验阶段，部分功能未完成。请仅在合法镜像 / 自测环境下使用。  
> **免责声明**：请在拥有合法授权的镜像 / 系统环境下使用。本项目不对外提供支持，也不承担任何损失或法律责任。  
> QEMU 在此处指代 Quick Emulator 模拟器，向 QEMU 上游生态致敬！  

---

## ✨ 核心特性（已实现 / 规划中）

- 在 MatePad / 鸿蒙电脑上运行 Windows 11 ARM、Linux ARM64  
- 离线连接能力：通过 hostfwd 实现宿主 ↔ 来宾端口映射（默认 RDP / VNC）  
- 安装阶段使用 VNC 界面，运行阶段默认用 RDP 嵌入视图渲染  
- 支持 **StartProgram**：在鸿蒙界面点击图标即可拉起指定 EXE 程序  
- 文件共享：RDP 驱动器重定向，把 App 沙箱目录映射为来宾盘符  
- 未来规划（正在路上）：媒体透传、快照/恢复、RemoteApp / RAIL、virtiofs / 9p / Samba、GPU / USB 虚拟支持  
- 探测降级机制：若宿主系统不暴露 `/dev/kvm`，自动降级为 TCG 模式运行  

> ⚠️ **注意事项 / 风险提示**  
> • 若无法访问 `/dev/kvm`，加速不可用 → 性能可能体验较差  
> • JIT / 可执行内存可能受到签名 / 权限限制  
> • 图形 / USB / 音频 / GPU 支持尚在开发中，不保证稳定  
> • 推荐在已知兼容设备 / 老版本系统上先行尝试，避免风险环境  

---

## 📦 环境与前置条件

- DevEco Studio 5 及以上 + HarmonyOS NEXT SDK（API 12+）  
- 开发者证书 + 调试签名，用于启用 JIT / 可执行内存  
- 目标设备：HarmonyOS NEXT 平板或电脑，开启开发者选项  
- 本地构建工具支持：cmake / meson / ninja / C/C++ toolchain  
- 若无完整 HarmonyOS NDK 环境，CMake 会自动回退为简易 NAPI shim，适配 CI / 原生验证环境  
- 仓库自带 `Native Build (Host)` workflow：Ubuntu Runner 检验原生代码能否通过基础编译  

---

## 🚀 快速上手指南

```bash
git clone https://github.com/caidingding233/qemu-hmos.git  
cd qemu-hmos  
# 到您的DevEco Studio App里面配置开发者证书 / 调试签名  
# 编译 QEMU / libqemu_full.so  
./configure --target-list=aarch64-softmmu --enable-tcg …  
make -j  
# 将产物放入 app/entry/libs/arm64-v8a/libqemu_full.so  
# 打包 hap 并部署到设备  
```

在 App 中：  
1. 新建虚拟机（Windows / Linux）  
2. 准备或下载 ISO / 镜像  
3. 使用 VNC 启动安装过程  
4. 安装完成后自动切换为 RDP 模式体验  

典型的 QEMU 启动参数（App 内生成）示例：  
```text
-machine virt,gic-version=3,virtualization=on
-cpu max -smp 4 -m 6144
-accel tcg,thread=multi,tb-size=128
-bios edk2-aarch64-code.fd
-drive if=none,id=d0,file=guest.qcow2,format=qcow2,cache=writeback,aio=threads,discard=unmap
-device nvme,drive=d0,serial=nvme0
-netdev user,id=n0,hostfwd=tcp:127.0.0.1:3390-:3389
-device virtio-net-pci,netdev=n0
```

---

## 📅 路线图与版本规划

| 阶段 | 功能重点 |
|------|-----------|
| MVP | QEMU 嵌入 + VNC / RDP 启动 + StartProgram + 文件映射 |
| V1 | 媒体透传 / 快照 / 恢复 / UI 优化 |
| V2+ | RemoteApp / RAIL / GPU 加速 / USB / virtiofs / 多系统模板 |

---

## 🧩 贡献指南

欢迎大家一起参与，特别需要的方向包括：  
- UI / 前端体验提升  
- 稳定性 / 性能优化 / Bug 修复  
- 新系统 / 来宾镜像模板支持  
- 媒体 / 图形 / USB / GPU 驱动适配  
- 文档 / 教程 / 示例镜像  

来吧，让我们一起把鸿蒙虚拟机打造成社区的骄傲！

---

## 📜 许可协议和隐私条款  

详见仓库 [LICENSE](LICENSE) 文件  
