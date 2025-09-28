# 本地构建 vs 云端构建说明

## 问题说明

你遇到的错误是因为脚本中硬编码了云端GitHub Actions的SDK路径 `/opt/harmonyos-sdk`，这个路径在你的本地Mac上根本不存在。

## 构建环境对比

### 本地Mac环境
- **系统**: macOS (darwin)
- **SDK路径**: 不存在 `/opt/harmonyos-sdk`
- **编译器**: 系统自带的gcc/clang
- **目标**: 只能构建Mac版本的库文件(.dylib)

### 云端GitHub Actions环境
- **系统**: Ubuntu 22.04 LTS
- **SDK路径**: `/opt/harmonyos-sdk` (通过workflow下载安装)
- **编译器**: HarmonyOS交叉编译器
- **目标**: 构建HarmonyOS版本的库文件(.so)

## 可用的构建脚本

### 1. Mac本地构建
```bash
# 在Mac上构建QEMU (不依赖HarmonyOS SDK)
./scripts/build-mac-local.sh
```

**特点**:
- ✅ 不需要HarmonyOS SDK
- ✅ 使用系统编译器
- ✅ 快速验证QEMU源码
- ❌ 生成Mac格式库文件(.dylib)
- ❌ 不能直接在HarmonyOS上使用

### 2. 云端构建
```bash
# 通过GitHub Actions构建HarmonyOS版本
# 在GitHub页面手动触发workflow
```

**特点**:
- ✅ 自动下载HarmonyOS SDK
- ✅ 使用正确的交叉编译器
- ✅ 生成HarmonyOS格式库文件(.so)
- ✅ 可以直接在HarmonyOS上使用
- ❌ 需要网络连接
- ❌ 构建时间较长

## 推荐的工作流程

### 开发阶段 (本地Mac)
1. **验证QEMU源码**: 使用 `./scripts/build-mac-local.sh`
2. **调试代码逻辑**: 在Mac上测试基本功能
3. **修改源码**: 使用本地工具链快速迭代

### 测试阶段 (云端)
1. **构建HarmonyOS版本**: 使用GitHub Actions
2. **下载构建产物**: 从workflow artifacts下载
3. **在HarmonyOS设备上测试**: 安装并运行

## 如何选择构建方式

### 选择本地构建的情况:
- 🔧 修改QEMU源码
- 🐛 调试编译错误
- ⚡ 快速验证代码
- 📱 不需要HarmonyOS特定功能

### 选择云端构建的情况:
- 📱 需要HarmonyOS格式的库文件
- 🚀 准备发布版本
- 🧪 在真实设备上测试
- 📦 需要完整的HarmonyOS功能

## 常见问题解决

### 问题1: "SDK root does not exist"
**原因**: 在本地Mac上运行了云端构建脚本

**解决方案**:
```bash
# 使用Mac本地构建脚本
./scripts/build-mac-local.sh
```

### 问题2: "dirname: missing operand"
**原因**: 脚本尝试在本地Mac上查找HarmonyOS SDK

**解决方案**:
```bash
# 使用Mac本地构建脚本
./scripts/build-mac-local.sh
```

### 问题3: 需要HarmonyOS格式的库文件
**原因**: 本地构建只能生成Mac格式的库文件

**解决方案**:
1. 使用GitHub Actions云端构建
2. 或者安装HarmonyOS SDK到本地

## 安装HarmonyOS SDK到本地 (可选)

如果你想在本地Mac上构建HarmonyOS版本，需要：

1. **下载HarmonyOS SDK**:
   ```bash
   # 从华为开发者网站下载
   # 或者使用脚本下载
   wget "https://contentcenter-vali-drcn.dbankcdn.cn/..."
   ```

2. **解压到本地目录**:
   ```bash
   unzip harmonyos-sdk.zip
   sudo mv commandline-tools /opt/harmonyos-sdk
   ```

3. **修改构建脚本**:
   ```bash
   # 修改scripts/build-qemu-simple.sh中的SDK路径
   SDK_ROOT="/opt/harmonyos-sdk"
   ```

## 总结

- **本地Mac**: 用于开发和调试，生成Mac格式库文件
- **云端GitHub**: 用于构建HarmonyOS版本，生成.so库文件
- **选择建议**: 开发用本地，发布用云端

记住：本地构建的库文件不能直接在HarmonyOS上使用，需要云端构建才能生成正确的格式！ 🎯
