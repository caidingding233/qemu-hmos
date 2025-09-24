#!/bin/bash

echo "=== 简单状态检查 ==="
echo "时间: $(date)"
echo

# 1. 检查设备连接
echo "1. 设备连接:"
hdc list targets
echo

# 2. 检查应用进程
echo "2. 应用进程:"
hdc shell ps | grep -E "(qemu|QEMU|caidingding|ing233)" | head -3
echo

# 3. 检查应用是否安装
echo "3. 应用安装状态:"
hdc shell pm list packages | grep -E "(qemu|caidingding)" | head -3
echo

# 4. 检查最近的日志
echo "4. 最近日志:"
hdc shell hilog -r | grep -E "(QEMU|VNC|NAPI)" | tail -5
echo

# 5. 检查网络端口
echo "5. 网络端口:"
hdc shell netstat -an | grep -E "(5901|5701)" | head -3
echo

echo "=== 检查完成 ==="