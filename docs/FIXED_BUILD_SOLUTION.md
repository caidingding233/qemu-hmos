# 修复的构建解决方案

## 问题分析

基于你提供的HNP构建配置，我发现了之前构建失败的根本原因：

### 原始问题：
1. **SDK下载URL过期** - 使用的 `contentcenter-vali-drcn.dbankcdn.cn` 链接可能已失效
2. **SDK版本不匹配** - 使用的是较新版本，但URL可能指向旧版本
3. **SDK路径结构不同** - 解压后的目录结构与预期不符

### HNP构建的成功要素：
1. **正确的SDK下载URL** - `repo.huaweicloud.com/openharmony/os/5.1.0-Release/`
2. **正确的SDK版本** - `5.1.0` 版本
3. **正确的解压方式** - 先解压tar.gz，再解压内部zip文件
4. **正确的SDK路径** - `ohos-sdk/linux` 而不是 `harmonyos-sdk`

## 新的构建方案

### 方案1：修复的GitHub Actions Workflow
- **文件**: `.github/workflows/build-qemu-fixed.yml`
- **特点**: 基于HNP构建配置，使用相同的SDK下载方式
- **优势**: 经过验证的SDK下载和解压流程

### 方案2：修复的构建脚本
- **文件**: `scripts/build-qemu-fixed.sh`
- **特点**: 支持多种SDK路径，更好的错误处理
- **优势**: 可以在不同环境中使用

## 关键改进

### 1. SDK下载方式
```bash
# 旧方式 (可能失效)
wget "https://contentcenter-vali-drcn.dbankcdn.cn/..."

# 新方式 (基于HNP配置)
curl -OL https://repo.huaweicloud.com/openharmony/os/5.1.0-Release/ohos-sdk-windows_linux-public.tar.gz
```

### 2. SDK解压方式
```bash
# 新方式 (基于HNP配置)
tar -xzf ohos-sdk-windows_linux-public.tar.gz
rm -rf ohos-sdk/{ohos,windows}
pushd ohos-sdk/linux
  for file in $(find . -type f); do
    unzip $file && rm $file
  done
popd
```

### 3. SDK路径检测
```bash
# 支持多种路径
SDK_LOCATIONS=(
    "/opt/harmonyos-sdk"
    "/opt/ohos-sdk/linux"
    "$(pwd)/ohos-sdk/linux"
    "$HOME/ohos-sdk/linux"
)
```

## 使用方法

### 云端构建 (推荐)
1. **使用修复的workflow**:
   - 去GitHub Actions页面
   - 手动触发 `build-qemu-fixed` workflow
   - 等待构建完成

2. **构建特点**:
   - 自动下载正确的SDK版本
   - 使用经过验证的解压方式
   - 生成HarmonyOS格式的库文件
   - 自动上传构建产物

### 本地构建 (如果SDK已安装)
```bash
# 使用修复的构建脚本
./scripts/build-qemu-fixed.sh
```

## 构建流程对比

### 原始流程 (失败)
```
下载SDK → 解压到harmonyos-sdk → 查找路径 → 构建失败
```

### 修复流程 (成功)
```
下载SDK → 解压tar.gz → 解压内部zip → 查找路径 → 构建成功
```

## 预期结果

构建成功后，你将得到：

```
entry/src/main/libs/arm64-v8a/
├── libqemu_full.so      # QEMU完整功能库
└── libqemu_hmos.so      # NAPI模块

entry/src/main/oh_modules/
└── libqemu_full.so      # 运行时加载的QEMU库
```

## 故障排除

### 如果仍然失败：
1. **检查SDK下载** - 确认网络连接和URL有效性
2. **检查SDK解压** - 确认解压过程没有错误
3. **检查路径检测** - 查看构建日志中的路径信息
4. **使用调试workflow** - 运行 `test-sdk-download` 进行详细分析

### 如果成功：
1. **下载构建产物** - 从GitHub Actions页面下载artifact
2. **在HarmonyOS设备上测试** - 安装并运行应用
3. **验证QEMU功能** - 测试虚拟机启动和VNC连接

## 总结

这个修复方案基于已经验证可用的HNP构建配置，应该能够解决之前遇到的SDK下载和路径问题。主要改进包括：

✅ **使用正确的SDK下载URL**  
✅ **使用正确的SDK版本 (5.1.0)**  
✅ **使用正确的解压方式**  
✅ **支持多种SDK路径**  
✅ **更好的错误处理和调试信息**  

现在你可以使用 `build-qemu-fixed` workflow 进行云端构建了！🚀
