#!/bin/bash

echo "=== QEMU鸿蒙版 - 全面调试脚本 ==="
echo "时间: $(date)"
echo

# 检查设备连接
echo "1. 检查设备连接状态..."
if hdc list targets | grep -q "127.0.0.1:5555"; then
    echo "✅ 设备已连接"
else
    echo "❌ 设备未连接，请先连接设备"
    exit 1
fi
echo

# 检查应用进程
echo "2. 检查应用进程状态..."
if hdc shell ps -ef | grep -q "com.cloudshin.aetherengine"; then
    echo "✅ 应用进程正在运行"
    hdc shell ps -ef | grep "com.cloudshin.aetherengine"
else
    echo "❌ 应用进程未运行"
fi
echo

# 检查应用包信息
echo "3. 检查应用包信息..."
hdc shell pm list packages | grep "com.cloudshin.aetherengine" || echo "❌ 应用包未找到"
echo

# 检查应用权限
echo "4. 检查应用权限..."
hdc shell dumpsys package com.cloudshin.aetherengine | grep -A 10 "requested permissions" || echo "❌ 无法获取权限信息"
echo

# 检查应用数据目录
echo "5. 检查应用数据目录..."
echo "检查 /data/storage/el2/base/haps/entry/..."
hdc shell ls -la /data/storage/el2/base/haps/entry/ 2>/dev/null || echo "❌ 目录不存在或无法访问"

echo "检查 /data/storage/el2/base/haps/entry/files/..."
hdc shell ls -la /data/storage/el2/base/haps/entry/files/ 2>/dev/null || echo "❌ 目录不存在或无法访问"

echo "检查 /data/storage/el2/base/haps/entry/libs/..."
hdc shell ls -la /data/storage/el2/base/haps/entry/libs/ 2>/dev/null || echo "❌ 目录不存在或无法访问"
echo

# 检查VM工作目录
echo "6. 检查VM工作目录..."
hdc shell ls -la /data/storage/el2/base/haps/entry/files/vm/ 2>/dev/null || echo "❌ VM目录不存在"
echo

# 检查库文件
echo "7. 检查库文件..."
echo "检查 libqemu_hmos.so..."
hdc shell find /data -name "libqemu_hmos.so" 2>/dev/null || echo "❌ libqemu_hmos.so 未找到"

echo "检查 libqemu_full.so..."
hdc shell find /data -name "libqemu_full.so" 2>/dev/null || echo "❌ libqemu_full.so 未找到"
echo

# 检查网络连接
echo "8. 检查网络连接..."
hdc shell netstat -an | grep -E ":(5901|5701)" || echo "❌ VNC端口未监听"
echo

# 检查QEMU进程
echo "9. 检查QEMU进程..."
hdc shell ps -ef | grep -i qemu || echo "❌ QEMU进程未运行"
echo

# 检查应用日志
echo "10. 检查应用日志..."
echo "最近的应用日志:"
hdc shell hilog -x | grep -i "qemu\|vnc\|aether" | tail -20 || echo "❌ 没有找到相关日志"
echo

# 检查系统错误
echo "11. 检查系统错误..."
echo "最近的系统错误:"
hdc shell hilog -x | grep -i "error\|fail\|denied" | tail -10 || echo "❌ 没有找到系统错误"
echo

# 检查应用安装状态
echo "12. 检查应用安装状态..."
hdc shell pm list packages -f | grep "com.cloudshin.aetherengine" || echo "❌ 应用未安装"
echo

# 检查应用版本
echo "13. 检查应用版本..."
hdc shell dumpsys package com.cloudshin.aetherengine | grep "versionName\|versionCode" || echo "❌ 无法获取版本信息"
echo

# 检查应用签名
echo "14. 检查应用签名..."
hdc shell dumpsys package com.cloudshin.aetherengine | grep -A 5 "signatures" || echo "❌ 无法获取签名信息"
echo

# 检查应用权限详情
echo "15. 检查应用权限详情..."
hdc shell dumpsys package com.cloudshin.aetherengine | grep -A 20 "requested permissions" || echo "❌ 无法获取权限详情"
echo

# 检查应用数据目录权限
echo "16. 检查应用数据目录权限..."
hdc shell ls -la /data/storage/el2/base/ | grep "com.cloudshin.aetherengine" || echo "❌ 应用数据目录不存在"
echo

# 检查应用缓存目录
echo "17. 检查应用缓存目录..."
hdc shell ls -la /data/storage/el2/base/haps/entry/cache/ 2>/dev/null || echo "❌ 缓存目录不存在"
echo

# 检查应用临时目录
echo "18. 检查应用临时目录..."
hdc shell ls -la /data/storage/el2/base/haps/entry/temp/ 2>/dev/null || echo "❌ 临时目录不存在"
echo

# 检查应用配置
echo "19. 检查应用配置..."
hdc shell cat /data/storage/el2/base/haps/entry/config.json 2>/dev/null || echo "❌ 配置文件不存在"
echo

# 检查应用状态
echo "20. 检查应用状态..."
hdc shell dumpsys package com.cloudshin.aetherengine | grep -A 10 "applicationInfo" || echo "❌ 无法获取应用状态"
echo

echo "=== 调试完成 ==="
echo "如果发现问题，请根据上述信息进行相应的修复"