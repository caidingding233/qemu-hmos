# QEMU鸿蒙版 - 完整路线图

## 项目愿景
**目标：打造"鸿蒙版 UTM"** - 在HarmonyOS设备上提供完整的虚拟机管理体验，实现与鸿蒙系统的"一体化"体验。

### 核心目标
- 网络 ✅、显示 ✅、ARM+X86 ✅
- 最终能跑 Windows 11 + Microsoft 365/OneDrive 在线服务
- 和鸿蒙的"一体化"体验（OneDrive/剪贴板/文件透传、柔光屏优化）

---

## 0) 总体策略（像 UTM 一样分层）

### Core（QEMU 内核）
- **aarch64-softmmu**（主力：Win11/Linux ARM）
- **x86_64-softmmu/i386-softmmu**（补充：Win10/11、macOS等的 x64 纯模拟）

### 显示层
- **安装期**：VNC
- **日常**：嵌入式 RDP（性能、缩放、中文字体渲染都更稳）

### 网络层
- **默认**：user,slirp + hostfwd
- **可选**：TUN/TAP（企业/高阶）

### 集成层（"像原生 App 一样"）
- **文件**：RDP 驱动器映射 +（可选）virtiofs/9p/Samba
- **剪贴板**：RDP 双向 Clipboard
- **"StartProgram"**：一键直达 Windows EXE
- **OneDrive 透传**：分三档实现
- **平台适配**：鸿蒙 PC/平板优先，手机端仅作为远程面板

---

## 1) 构建：把 ARM 与 X86 一次搞定

### 扩展 target-list 为三件套
```bash
../configure \
  --target-list=aarch64-softmmu,x86_64-softmmu,i386-softmmu \
  --cc="$CC" --cxx="$CXX" --host-cc="/usr/bin/cc" \
  --extra-cflags="--sysroot=${SYSROOT} -fPIC" \
  --extra-ldflags="--sysroot=${SYSROOT}" \
  --disable-gtk --disable-sdl --disable-spice --disable-vte \
  --disable-gnutls --disable-nettle --disable-gcrypt --disable-libssh \
  --enable-slirp --enable-vnc \
  -Dwrap_mode=forcefallback \
  --meson=meson
ninja -j$(nproc)
```

### 为什么同时编 aarch64 + x86
- **主力推荐**：Win11 ARM → 在 ARM 上跑 ARM 指令（虽无 KVM，但比跨指令集快），再用 Windows 自带 x86/x64 应用层仿真运行 Office/老软件
- **备胎**：纯 x86_64 来宾（Win10/11 x64）→ 完全跨指令集 TCG，能跑，但慢，仅用于兼容验证/展示

---

## 2) 来宾创建：两条路线

### A. Windows 11 ARM（推荐）
更现实的"可用生产力"方案；微软官方已内置 x86/x64 应用兼容层。

```bash
# 典型 Win11 ARM VM
qemu-system-aarch64 \
  -machine virt,gic-version=3,virtualization=on \
  -cpu max -smp 4 -m 6144 \
  -accel tcg,thread=multi,tb-size=128 \
  -bios edk2-aarch64-code.fd \
  -device virtio-gpu-pci \
  -device nec-usb-xhci -device usb-kbd -device usb-mouse \
  -drive if=none,id=nv,file=win11arm.qcow2,format=qcow2,cache=writeback,aio=threads,discard=unmap \
  -device nvme,drive=nv,serial=nvme0 \
  -cdrom Win11_ARM.iso \
  -netdev user,id=n0,hostfwd=tcp:127.0.0.1:3390-:3389 \
  -device virtio-net-pci,netdev=n0 \
  -vnc :1
```

### B. Windows 10/11 x64（仅备选）
可以，但性能远逊。命令与上面类似，改为 qemu-system-x86_64 并选对应 OVMF/virtio 设备。

---

## 3) 网络：让 M365/OneDrive"开箱可登录"

### 默认配置
- **-netdev user（slirp）**足够：HTTP(S)、DNS、RDP 都 OK
- **常见转发表**：
  - `hostfwd=tcp:127.0.0.1:3390-:3389`（RDP）
  - `hostfwd=tcp:127.0.0.1:2222-:22`（SSH，Linux 来宾时）

### 企业级选项
要企业级/低延迟：切 TUN/TAP（App 提供"高级网络模式"，引导用户安装/授权）

---

## 4) OneDrive / Microsoft 365 集成（三档落地）

### 档位 1：纯来宾内安装（最快上线）
- 在 Win11 ARM 内直接安装 OneDrive/Office/Microsoft Store，开机自启
- App 端做自动化：首启脚本启用 RDP、同步时区/证书、安装 Edge/OneDrive

### 档位 2：Guest→Host 映射（"像原生"体验）
- 首先呢 就是在Host里面**新建一个文件夹作为OneDrive的映射文件夹** 
- 然后呢 在客户机里面把**OneDrive映射到一个共享磁盘** 映射到刚刚在鸿蒙侧搞的这个OneDrive的映射文件夹     
- 然后呢 鸿蒙主机则是把他映射到App沙箱内的**OneDrive 文件夹**   
- **体验**：用户把文件放进鸿蒙的 OneDrive 文件夹，来宾里立刻看到；反之亦然（靠 App 后台映射和同步）

### 档位 3：virtiofs/9p/Samba（高阶）
- 给 Linux 来宾：优先 virtiofs / 9p（真共享）
- 给 Windows 来宾：可选 Samba 共享（App 内置小型 SMB 服务）或关注 Windows virtiofs 驱动（适配成本较高）
- **提示**：Samba 要处理权限/来宾帐号、局域网可见性

**建议上线顺序**：先档位 1 → 档位 2（同步做成可选插件）→ 研究档位 3

---

## 5) 显示与"柔光屏"优化

### 安装期 VNC
- `-vnc :1`，App 内置 VNC 视图即可

### 日常用 RDP
嵌入 FreeRDP 类组件，拿到：
- **HiDPI 缩放**（适配"柔光"/低反射屏幕）
- **剪贴板/驱动器/IME 更好**
- **视频/滚动更流畅**

### 细节建议
- RDP 端设 `gfx-h264:prefer` 或智能画质（组件支持时）
- **字体渲染**：Windows 端开 ClearType
- **App 端 Surface**：采用独立渲染线程 + VSync 对齐
- **提供"锐度 / 抗锯齿 / 对比度"三滑条**，记每 VM 的偏好

---

## 6) 和鸿蒙的"像原生"整合

### StartProgram
安装一个代理App 每次启动这个代理App 这个App则会连接到虚拟机的RemoteApp 来形成完整的映射

### 桌面/服务卡片
将"虚拟机/应用"钉到桌面（PC和平板：服务卡片）

### 剪贴板
RDP 自带；对纯 VNC 提供"复制/粘贴桥"

### 通知
来宾端邮件/消息→RDP 通知→App 转为鸿蒙通知（可配置免打扰）

### 电源联动
VM 休眠/快照/关机，一键完成

### 文件拽投
拖文件到 App 窗口→落到来宾桌面/下载目录（RDP 驱动器/桥接实现）

---

## 7) 权限与封装（HarmonyOS NEXT）

### PC/2in1 优先；手机端仅"远程面板"，不发 CLI

### 建议申请权限（按需取舍）

#### JIT/可执行内存（跑 TCG 很关键，仅平板/PC）
- `ohos.permission.kernel.ALLOW_WRITABLE_CODE_MEMORY`
- `ohos.permission.kernel.ALLOW_EXECUTABLE_FORT_MEMORY` 或 `ALLOW_USE_JITFORT_INTERFACE`

#### 浮窗/虚拟屏/输入
- `ohos.permission.SYSTEM_FLOAT_WINDOW`（2in1/平板）
- `ohos.permission.ACCESS_VIRTUAL_SCREEN`（投屏/多视图）
- `ohos.permission.INTERCEPT_INPUT_EVENT` / `INPUT_MONITORING`（远程/云桌面类）

#### 文件与桌面
- `ohos.permission.READ_WRITE_DESKTOP_DIRECTORY`（2in1/平板）
- `ohos.permission.READ_WRITE_USER_FILE`（IDE/高阶文件操作，白名单制）

#### USB/HID（可选，做 U 盘/手柄直通）
- `ohos.permission.ACCESS_DDK_USB` / `ACCESS_DDK_HID`

### 打包策略
- **PC/平板 HAP（全量）**：带 QEMU .so + 嵌入式 RDP/VNC + "StartProgram"
- **手机 HAP（轻量）**：仅远程面板（连接到平板/PC 上的 VM）
- **CLI**：走 HNP（仅 PC/2in1 发放），签名与分发和 UI 包分离

---

## 8) 典型"开箱即用"流水线

1. **首次启动** → 引导下载/导入 EDK2 固件、Win11 ARM ISO
2. **一键创建 VM**（预设 NVMe、virtio-net、内存 6–8 GB）
3. **启动安装（VNC）** → 装好后 App 自动：
   - 启用 RDP、开放 3389、防睡眠
   - 安装 Edge / OneDrive / 字体包
   - 写入来宾的脚本以支持 StartProgram
   - 挂载 Z:（RDP 驱动器）→ 对应鸿蒙侧 "OneDrive 缓存目录"
4. **日常**：点"Word/Excel/OneDrive"卡片→ 直连 RDP → 秒进应用
5. **备份**：快照/休眠/恢复；VM 镜像（qcow2）做差分备份

---

## 9) CLI 示例（给开发者/重度用户）

```bash
# 用"原生 QEMU 子命令"创建
qemu -original qemu-system-aarch64 \
  -machine virt,gic-version=3,virtualization=on \
  -cpu max -smp 4 -m 6144 \
  -accel tcg,thread=multi,tb-size=128 \
  -bios edk2-aarch64-code.fd \
  -device virtio-gpu-pci \
  -device nec-usb-xhci -device usb-kbd -device usb-mouse \
  -drive if=none,id=nv,file=win11arm.qcow2,format=qcow2,cache=writeback,aio=threads,discard=unmap \
  -device nvme,drive=nv,serial=nvme0 \
  -cdrom Win11_ARM.iso \
  -netdev user,id=n0,hostfwd=tcp:127.0.0.1:3390-:3389 \
  -device virtio-net-pci,netdev=n0 \
  -vnc :1

# 启动（暴露 RDP 转发）
qemu -original qemu-system-x86_64 \
-m 4096 \
-smp 4 \
-hda /path/to/disk_image.img \
-cdrom /path/to/cd_image.iso \
-boot d

# 管理器：文件传输 / 执行命令 / 电源 / 客户机命令行
qemu -manager copy --vm Win11ARM --from host:/sandbox/onedrive/ --to guest:Z:/
qemu -manager exec --vm Win11ARM -- "powershell Start-Process notepad.exe"
qemu -manager power --vm Win11ARM --suspend
qemu -manager power --vm Win11ARM --off
qemu -manager shell --vm Linux -c "whoami"
```

**普通用户全部走 UI；CLI 仅 2in1/平板 下发**

---

## 10) 性能与预期

- **Win11/Linux ARM**：在纯 TCG 下也能达到"可办公"的档位（RDP 渲染帮助很大）
- **x86_64 Guest**：能跑，但较慢；只做兼容备用
- **RDP 对 HiDPI/柔光屏体验提升显著**；VNC 仅用于安装/紧急救援

---

## 11) 下一步清单（从 0 到 1）

1. **在 CI 里把 --target-list 扩到 aarch64,x86_64,i386**（见 §1）
2. **App 内集成 VNC + RDP**，默认"装系统走 VNC，日常走 RDP"
3. **首启脚本（来宾）落地**：RDP 开启、OneDrive/Office 安装、Z: 映射
4. **做 "OneDrive 缓存目录" 与 RDP 驱动器 绑定**（档位 2）
5. **做"StartProgram"与"桌面卡片"**
6. **权限与分发策略**（PC/平板/手机分层）
7. **（可选）研究 virtiofs/Samba**；评估 gnutls + TLS 通道

---

## 实现优先级

### Phase 1: 核心功能（4周内）
- [x] QEMU 多目标构建支持
- [x] VNC/RDP 显示层集成
- [x] 基础 VM 管理功能
- [ ] OneDrive 档位1集成
- [ ] StartProgram 功能

### Phase 2: 原生集成（8周内）
- [ ] OneDrive 档位2（RDP驱动器映射）
- [ ] 桌面卡片和服务
- [ ] 剪贴板和通知集成
- [ ] 权限申请和封装

### Phase 3: 高级功能（12周内）
- [ ] 快照和备份系统
- [ ] CLI 工具集
- [ ] 性能优化
- [ ] OneDrive 档位3（virtiofs/Samba）

---

*这个路线图将 QEMU-HarmonyOS 项目定位为真正的"鸿蒙版 UTM"，提供完整的虚拟机管理体验和与鸿蒙系统的深度集成。*
