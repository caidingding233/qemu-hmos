#!/bin/bash

echo "=== VNC连接问题详细诊断 ==="
echo "时间: $(date)"
echo

# 1. 检查应用进程
echo "1. 应用进程状态:"
hdc shell ps | grep -E "(qemu|QEMU|caidingding|ing233)" | head -5
echo

# 2. 检查应用权限
echo "2. 检查应用权限:"
hdc shell dumpsys package com.caidingding233.qemuhmos 2>/dev/null | grep -A 10 "requested permissions" | head -15
echo

# 3. 检查应用数据目录
echo "3. 检查应用数据目录:"
hdc shell ls -la /data/storage/el2/base/haps/entry/ 2>/dev/null | head -10
echo

# 4. 检查VM工作目录
echo "4. 检查VM工作目录:"
hdc shell ls -la /data/storage/el2/base/haps/entry/files/ 2>/dev/null | head -10
echo

# 5. 检查库文件
echo "5. 检查库文件:"
hdc shell ls -la /data/storage/el2/base/haps/entry/libs/ 2>/dev/null | head -10
echo

# 6. 检查网络连接
echo "6. 检查网络连接:"
hdc shell netstat -an | grep -E "(5901|5701|127.0.0.1)" | head -5
echo

# 7. 检查QEMU进程
echo "7. 检查QEMU进程:"
hdc shell ps | grep -E "(qemu-system|qemu)" | head -5
echo

# 8. 检查应用日志
echo "8. 检查应用日志:"
hdc shell hilog -r | grep -E "(QEMU|VNC|NAPI|TestFunction|VNC_NATIVE|StartVm)" | tail -10
echo

# 9. 检查系统错误
echo "9. 检查系统错误:"
hdc shell hilog -r | grep -E "(ERROR|FATAL|SEGV|SIGBUS)" | tail -5
echo

echo "=== 诊断完成 ==="

