#!/bin/bash

# QEMU-HarmonyOS NAPI修复验证脚本
# 用于测试NAPI模块加载修复效果

echo "=== QEMU-HarmonyOS NAPI修复验证 ==="
echo "时间: $(date)"
echo

# 检查项目结构
echo "1. 检查项目结构..."
if [ -f "entry/src/main/cpp/napi_init.cpp" ]; then
    echo "✅ napi_init.cpp 存在"
else
    echo "❌ napi_init.cpp 不存在"
    exit 1
fi

if [ -f "entry/src/main/ets/types/qemu_hmos.d.ts" ]; then
    echo "✅ qemu_hmos.d.ts 类型声明文件存在"
else
    echo "❌ qemu_hmos.d.ts 类型声明文件不存在"
fi

# 检查关键修改
echo
echo "2. 检查关键修改..."

# 检查模块名修改
if grep -q "nm_modname = \"qemu_hmos\"" entry/src/main/cpp/napi_init.cpp; then
    echo "✅ NAPI模块名已修改为 qemu_hmos"
else
    echo "❌ NAPI模块名未正确修改"
fi

# 检查ArkTS导入修改
if grep -q "import qemu from 'qemu_hmos'" entry/src/main/ets/pages/Index.ets; then
    echo "✅ ArkTS导入已修改为 qemu_hmos"
else
    echo "❌ ArkTS导入未正确修改"
fi

# 检查新增的调试函数
if grep -q "GetModuleInfo" entry/src/main/cpp/napi_init.cpp; then
    echo "✅ 新增GetModuleInfo调试函数"
else
    echo "❌ 缺少GetModuleInfo调试函数"
fi

# 检查HILOG增强
if grep -q "Environment pointer" entry/src/main/cpp/napi_init.cpp; then
    echo "✅ HILOG调试信息已增强"
else
    echo "❌ HILOG调试信息未增强"
fi

echo
echo "3. 构建测试..."
echo "运行构建命令: hvigor assembleDebug"

# 检查是否有hvigor
if command -v hvigor &> /dev/null; then
    echo "✅ hvigor 命令可用"
    echo "建议运行: hvigor assembleDebug"
else
    echo "⚠️  hvigor 命令不可用，请使用DevEco Studio构建"
fi

echo
echo "4. 验证步骤..."
echo "构建完成后，请执行以下验证步骤："
echo "1. 安装HAP到设备: hdc install -r ./entry/build/outputs/hap/*.hap"
echo "2. 启动应用并查看日志: hdc shell hilog -x | grep QEMU"
echo "3. 点击'诊断依赖'按钮查看核心库状态"
echo "4. 检查是否出现以下关键日志："
echo "   - 'QEMU: NAPI module constructor running, registering qemu_hmos'"
echo "   - 'QEMU: NAPI Init function called!'"
echo "   - 'QEMU: TestFunction - NAPI module is working correctly!'"

echo
echo "5. 预期结果..."
echo "如果修复成功，应该看到："
echo "✅ NAPI模块正确加载"
echo "✅ C++调试日志正常输出"
echo "✅ testFunction和getModuleInfo调用成功"
echo "✅ VM启动时QEMU进程真正运行"

echo
echo "=== 验证完成 ==="
echo "如有问题，请检查："
echo "1. 设备是否支持JIT权限"
echo "2. 开发者证书是否正确配置"
echo "3. 库文件是否正确打包到HAP中"
echo "4. 设备日志中的具体错误信息"

