# 正确的构建方式说明

## 问题澄清

你完全正确！我之前的理解有误：

### HNP构建 vs 我们的需求：
- **HNP (HarmonyOS Native Package)**: 构建独立的可执行文件，可以直接在HarmonyOS上运行
- **我们的需求**: 构建共享库(.so文件)，集成到HarmonyOS应用中通过NAPI调用

### 关键差异：
1. **HNP**: 使用 `make -C build-hnp` 构建可执行文件
2. **我们**: 需要构建 `libqemu_hmos.so` 和 `libqemu_full.so` 共享库

## 正确的构建方案

### 方案1：使用修复的SDK下载方式构建共享库
- **Workflow**: `build-shared-libs.yml`
- **目标**: 构建共享库(.so文件)用于HarmonyOS应用集成
- **特点**: 使用HNP的SDK下载方式，但构建我们的共享库

### 方案2：使用系统交叉编译器
- **Workflow**: `build-with-system-tools.yml`
- **目标**: 不依赖HarmonyOS SDK，使用系统工具构建
- **特点**: 更稳定，避免SDK下载问题

## 构建目标对比

### HNP构建 (不适合我们)：
```
输入: QEMU源码
输出: 独立的可执行文件
用途: 直接在HarmonyOS上运行
集成: 不需要，独立运行
```

### 我们的构建 (正确方式)：
```
输入: QEMU源码 + NAPI代码
输出: 共享库(.so文件)
用途: 集成到HarmonyOS应用中
集成: 通过NAPI调用QEMU功能
```

## 正确的构建流程

### 1. 构建QEMU静态库
```bash
# 配置QEMU构建静态库
../configure --target-list=aarch64-softmmu --cross-prefix=aarch64-unknown-linux-ohos- ...

# 构建静态库
make -j$(nproc)
# 生成: libqemu-aarch64-softmmu.a, libqemuutil.a
```

### 2. 创建QEMU共享库
```bash
# 将静态库链接成共享库
$CXX -shared -fPIC -Wl,--whole-archive \
  libqemu-aarch64-softmmu.a libqemuutil.a \
  -Wl,--no-whole-archive -o libqemu_full.so
```

### 3. 构建NAPI模块
```bash
# 构建NAPI桥接模块
cmake .. -DCMAKE_C_COMPILER="$CC" ...
make -j$(nproc)
# 生成: libqemu_hmos.so
```

### 4. 集成到HarmonyOS应用
```typescript
// 在ArkTS中调用
import qemu from 'qemu_hmos';
qemu.startVM(config);
```

## 推荐使用方案

### 方案1：修复的SDK构建 (推荐)
```bash
# 使用GitHub Actions
# 手动触发 build-shared-libs workflow
```

**优势**:
- 使用正确的SDK下载方式
- 构建HarmonyOS格式的共享库
- 可以直接在HarmonyOS应用中使用

### 方案2：系统工具构建 (备选)
```bash
# 使用GitHub Actions
# 手动触发 build-with-system-tools workflow
```

**优势**:
- 不依赖HarmonyOS SDK
- 使用系统交叉编译器
- 更稳定可靠

## 构建产物说明

### 成功构建后得到：
```
entry/src/main/libs/arm64-v8a/
├── libqemu_full.so      # QEMU核心功能库
└── libqemu_hmos.so      # NAPI模块

entry/src/main/oh_modules/
└── libqemu_full.so      # 运行时加载的QEMU库
```

### 库文件用途：
- **libqemu_full.so**: 包含QEMU虚拟机引擎，提供虚拟机功能
- **libqemu_hmos.so**: NAPI模块，提供ArkTS到QEMU的桥接接口

## 集成到HarmonyOS应用

### 1. 库文件部署
```bash
# 将.so文件复制到应用目录
cp libqemu_full.so entry/src/main/libs/arm64-v8a/
cp libqemu_hmos.so entry/src/main/libs/arm64-v8a/
```

### 2. NAPI调用
```typescript
// 在ArkTS中调用QEMU功能
import qemu from 'qemu_hmos';

// 启动虚拟机
qemu.startVM({
  memory: '2G',
  cpu: '4',
  disk: '/path/to/disk.img'
});

// 连接VNC
qemu.connectVNC('localhost:5900');
```

### 3. 应用打包
```bash
# 构建HarmonyOS应用
hvigor assembleHap
# 生成: *.hap文件
```

## 总结

正确的构建方式是：
1. **使用HNP的SDK下载方式** (解决SDK问题)
2. **但构建共享库而不是可执行文件** (满足我们的需求)
3. **生成.so文件用于HarmonyOS应用集成** (正确的集成方式)

这样既解决了SDK下载问题，又保持了我们的构建目标！🎯
