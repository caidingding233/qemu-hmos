#!/bin/bash

echo "=== QEMU鸿蒙版当前状态诊断 ==="
echo "时间: $(date)"
echo

# 检查设备连接
echo "1. 检查设备连接状态:"
hdc list targets
echo

# 检查应用是否安装
echo "2. 检查应用安装状态:"
hdc shell pm list packages | grep qemu
echo

# 检查应用文件结构
echo "3. 检查应用文件结构:"
hdc shell ls -la /data/app/el2/100/base/com.caidingding233.qemuhmos/haps/entry/libs/arm64-v8a/ 2>/dev/null || echo "libs目录不存在"
echo

# 检查核心库文件
echo "4. 检查核心库文件:"
hdc shell ls -la /data/app/el2/100/base/com.caidingding233.qemuhmos/haps/entry/libs/arm64-v8a/libqemu_full.so 2>/dev/null || echo "libqemu_full.so不存在"
hdc shell ls -la /data/app/el2/100/base/com.caidingding233.qemuhmos/haps/entry/libs/arm64-v8a/libqemu_hmos.so 2>/dev/null || echo "libqemu_hmos.so不存在"
echo

# 检查VM目录
echo "5. 检查VM工作目录:"
hdc shell ls -la /data/storage/el2/base/haps/entry/files/vms/ 2>/dev/null || echo "VM目录不存在"
echo

# 检查最近的日志
echo "6. 检查最近的QEMU相关日志:"
hdc shell hilog -r | grep -E "(QEMU|VNC|NAPI)" | tail -10
echo

# 检查应用进程
echo "7. 检查应用进程状态:"
hdc shell ps | grep qemu
echo

echo "=== 诊断完成 ==="
