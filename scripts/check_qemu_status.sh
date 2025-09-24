#!/bin/bash
echo "=== QEMU状态检查脚本 ==="
echo ""

echo "1. 检查设备连接..."
hdc list targets
echo ""

echo "2. 检查应用进程..."
echo "QEMU相关进程:"
hdc shell ps | grep -i qemu || echo "没有找到QEMU进程"
echo ""

echo "3. 检查最新日志..."
echo "VNC相关日志:"
hdc shell hilog -x | grep -E "(VNC_NATIVE|VNC_CLIENT)" | tail -5
echo ""

echo "4. 检查诊断状态..."
echo "核心库状态:"
hdc shell hilog -x | grep -E "(Core\.loaded|Core\.symFound)" | tail -3
echo ""

echo "5. 建议操作:"
echo "   - 如果没有看到新日志，请重新启动应用"
echo "   - 点击'诊断依赖'查看详细状态"
echo "   - 如果仍有问题，可能需要重新编译"
