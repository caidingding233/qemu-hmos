#!/bin/bash

echo "=== QEMU鸿蒙版全面诊断 ==="
echo "时间: $(date)"
echo

# 1. 检查设备连接
echo "1. 设备连接状态:"
hdc list targets
echo

# 2. 检查应用进程
echo "2. 应用进程状态:"
hdc shell ps | grep -E "(qemu|QEMU|caidingding|ing233)" | head -5
echo

# 3. 检查应用包信息
echo "3. 应用包信息:"
hdc shell pm list packages | grep -E "(qemu|caidingding)" | head -5
echo

# 4. 检查应用权限
echo "4. 应用权限:"
hdc shell dumpsys package com.caidingding233.qemuhmos 2>/dev/null | grep -A 5 "requested permissions" | head -10
echo

# 5. 检查应用数据目录
echo "5. 应用数据目录:"
hdc shell ls -la /data/storage/el2/base/haps/entry/ 2>/dev/null | head -10
echo

# 6. 检查VM工作目录
echo "6. VM工作目录:"
hdc shell ls -la /data/storage/el2/base/haps/entry/files/ 2>/dev/null | head -10
echo

# 7. 检查库文件
echo "7. 库文件检查:"
hdc shell ls -la /data/storage/el2/base/haps/entry/libs/ 2>/dev/null | head -10
echo

# 8. 检查最近的日志
echo "8. 最近的应用日志:"
hdc shell hilog -r | grep -E "(QEMU|VNC|NAPI|TestFunction|VNC_NATIVE)" | tail -10
echo

# 9. 检查系统日志
echo "9. 系统日志:"
hdc shell hilog -r | tail -20
echo

# 10. 检查网络连接
echo "10. 网络连接检查:"
hdc shell netstat -an | grep -E "(5901|5701)" | head -5
echo

echo "=== 诊断完成 ==="
