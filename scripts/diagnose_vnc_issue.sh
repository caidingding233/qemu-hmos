#!/bin/bash
echo "=== VNC启动失败诊断脚本 ==="
echo ""

echo "1. 检查本地文件状态:"
echo "   libqemu_full.so (oh_modules): $(ls -la entry/oh_modules/libqemu_full.so 2>/dev/null && echo '✅ 存在' || echo '❌ 缺失')"
echo "   libqemu_hmos.so (oh_modules): $(ls -la entry/oh_modules/libqemu_hmos.so 2>/dev/null && echo '✅ 存在' || echo '❌ 缺失')"
echo "   HAP文件: $(ls -la entry/build/default/outputs/default/entry-default-signed.hap 2>/dev/null && echo '✅ 存在' || echo '❌ 缺失')"
echo ""

echo "2. 检查HAP内容:"
echo "   库文件列表:"
unzip -l entry/build/default/outputs/default/entry-default-signed.hap 2>/dev/null | grep -E "lib.*\.so$" | while read line; do
    echo "   $line"
done
echo ""

echo "3. 可能的解决方案:"
echo "   a) 重新安装应用到设备"
echo "   b) 检查设备存储权限"
echo "   c) 查看设备日志中的详细错误信息"
echo "   d) 尝试使用'诊断依赖'功能检查运行时状态"
echo ""

echo "4. 运行时检查命令:"
echo "   hdc shell hilog -x | grep -E '(QEMU_CORE|VNC_NATIVE)'"
echo ""

echo "5. 建议的调试步骤:"
echo "   1. 重新编译: hvigor assembleDebug"
echo "   2. 重新安装: hdc install -r entry/build/default/outputs/default/entry-default-signed.hap"
echo "   3. 启动应用，进入'诊断依赖'页面"
echo "   4. 查看Core状态和错误信息"
echo "   5. 如果仍有问题，提供完整的设备日志"
