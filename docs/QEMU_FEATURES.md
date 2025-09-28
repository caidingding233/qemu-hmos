# QEMU功能配置说明

## 启用的功能

### 显示和远程访问
- **VNC**: `--enable-vnc` - 启用VNC远程桌面
- **VNC JPEG**: `--enable-vnc-jpeg` - VNC JPEG压缩
- **VNC PNG**: `--enable-vnc-png` - VNC PNG压缩  
- **VNC SASL**: `--enable-vnc-sasl` - VNC安全认证

### 网络功能
- **SLIRP**: `--enable-slirp` - 用户模式网络栈，支持NAT
- **CURL**: `--enable-curl` - HTTP/HTTPS下载支持
- **VHOST-NET**: `--enable-vhost-net` - 高性能网络
- **VHOST-KERNEL**: `--enable-vhost-kernel` - 内核加速网络

### 存储和I/O
- **VHOST-USER**: `--enable-vhost-user` - 用户态存储后端
- **VHOST-USER-BLK-SERVER**: `--enable-vhost-user-blk-server` - 块设备服务器
- **LIBVDUSE**: `--enable-libvduse` - VDUSE库支持
- **VDUSE-BLK-EXPORT**: `--enable-vduse-blk-export` - VDUSE块设备导出

### 系统功能
- **FDT**: `--enable-fdt` - 设备树支持
- **GUEST-AGENT**: `--enable-guest-agent` - 客户机代理
- **KEYRING**: `--enable-keyring` - 密钥环支持

### 虚拟化
- **TCG**: `--enable-tcg` - 动态代码生成器

## 支持的功能

### 1. VNC远程桌面
```bash
# 启动VNC服务器
qemu-system-aarch64 -vnc :0 -monitor stdio
# 连接: localhost:5900
```

### 2. 网络连接
```bash
# 用户模式网络 (NAT)
-netdev user,id=net0,hostfwd=tcp::2222-:22

# 桥接网络
-netdev bridge,id=net0,br=br0
```

### 3. 存储设备
```bash
# 硬盘
-drive file=disk.img,format=qcow2

# CD/DVD
-drive file=install.iso,media=cdrom

# USB设备透传
-device usb-host,vendorid=0x1234,productid=0x5678
```

### 4. 设备透传
```bash
# USB设备
-device usb-host,vendorid=0x1234,productid=0x5678

# PCI设备
-device vfio-pci,host=01:00.0
```

### 5. 共享文件夹
```bash
# 9p文件系统
-fsdev local,id=fsdev0,path=/host/path,security_model=passthrough
-device virtio-9p-pci,fsdev=fsdev0,mount_tag=host
```

## 在HarmonyOS中的应用

### 1. VNC连接
```typescript
// 启动虚拟机并启用VNC
qemu.startVM({
  vnc: {
    port: 5900,
    password: 'optional'
  }
});

// 连接VNC
qemu.connectVNC('localhost:5900');
```

### 2. 网络配置
```typescript
// 配置网络
qemu.startVM({
  network: {
    type: 'user', // 或 'bridge'
    hostfwd: [
      { host: 2222, guest: 22 },   // SSH
      { host: 8080, guest: 80 },   // HTTP
      { host: 8443, guest: 443 }   // HTTPS
    ]
  }
});
```

### 3. 存储设备
```typescript
// 添加存储设备
qemu.startVM({
  drives: [
    { file: 'disk.img', format: 'qcow2' },
    { file: 'install.iso', media: 'cdrom' }
  ]
});
```

### 4. USB设备
```typescript
// USB设备透传
qemu.startVM({
  usb: [
    { vendorid: '0x1234', productid: '0x5678' }
  ]
});
```

## 功能对比

### 之前 (功能受限):
```
❌ 无VNC远程桌面
❌ 无网络连接
❌ 无存储设备支持
❌ 无USB透传
❌ 无共享文件夹
```

### 现在 (功能完整):
```
✅ VNC远程桌面 (JPEG/PNG压缩)
✅ 网络连接 (NAT/桥接)
✅ 存储设备 (硬盘/CD/USB)
✅ USB设备透传
✅ 共享文件夹 (9p文件系统)
✅ 客户机代理
✅ 设备树支持
```

## 使用场景

### 1. 桌面虚拟机
- VNC远程桌面访问
- 完整的图形界面
- 网络连接和文件共享

### 2. 服务器虚拟机
- 网络服务部署
- 存储设备管理
- 远程管理接口

### 3. 开发环境
- 共享文件夹开发
- USB设备调试
- 网络服务测试

### 4. 多媒体应用
- 音频/视频设备
- 游戏手柄支持
- 摄像头设备

## 注意事项

### 1. 性能考虑
- VNC压缩会影响性能
- 网络模式影响速度
- 存储格式影响I/O性能

### 2. 安全考虑
- VNC密码保护
- 网络访问控制
- USB设备权限

### 3. 兼容性
- 某些功能需要客户机支持
- 设备透传需要权限
- 网络配置需要系统支持

## 总结

现在QEMU构建包含了完整的功能集，支持：
- 🖥️ **VNC远程桌面** - 完整的图形界面访问
- 🌐 **网络连接** - NAT和桥接网络
- 💾 **存储设备** - 硬盘、CD、USB支持
- 🔌 **设备透传** - USB和PCI设备
- 📁 **文件共享** - 9p文件系统
- 🔧 **系统管理** - 客户机代理和设备树

这样构建的QEMU可以满足各种虚拟机使用场景！🚀
