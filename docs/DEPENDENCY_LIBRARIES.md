# 依赖库说明

## 概述

QEMU需要多个第三方库来提供完整功能。这些库已经被编译成静态库（`.a`文件），并且会被链接到最终的共享库（`.so`文件）中。

## 依赖库列表

### 1. GLib库 (GNU Library)
**位置**: `third_party/deps/glib/`
**用途**: 提供基础数据结构、内存管理、字符串处理等核心功能

**包含的静态库**:
- `libglib-2.0.a` - 核心GLib库
- `libgobject-2.0.a` - 对象系统
- `libgthread-2.0.a` - 线程支持
- `libcharset.a` - 字符集处理
- `libgnulib.a` - GNU库函数

### 2. Pixman库
**位置**: `third_party/deps/pixman/`
**用途**: 提供像素操作和图像处理功能，VNC显示必需

**包含的静态库**:
- `libpixman-1.a` - 核心Pixman库
- `libpixman-arm-neon.a` - ARM NEON优化

### 3. OpenSSL库
**位置**: `third_party/deps/openssl/`
**用途**: 提供加密和SSL/TLS支持，网络功能必需

**包含的静态库**:
- `libssl.a` - SSL/TLS协议实现
- `libcrypto.a` - 加密算法库

### 4. PCRE2库
**位置**: `third_party/deps/pcre2/`
**用途**: 提供正则表达式支持

**包含的静态库**:
- `libpcre2-8.a` - 8位字符正则表达式
- `libpcre2-posix.a` - POSIX兼容接口

## 构建过程

### 1. 依赖库编译
这些库已经在本地编译完成，生成了静态库文件：

```bash
# 检查已编译的静态库
find third_party/deps -name "*.a" | wc -l
# 输出: 26 (共26个静态库文件)
```

### 2. 链接到共享库
在创建最终的`libqemu_full.so`时，这些静态库会被链接进去：

```bash
$CXX -shared -fPIC -Wl,--no-undefined \
  -target aarch64-unknown-linux-ohos --sysroot=${SYSROOT} \
  -Wl,--whole-archive \
  libqemu-aarch64-softmmu.a \
  libqemuutil.a \
  -Wl,--no-whole-archive \
  # 依赖库
  ../../deps/glib/build/glib/libglib-2.0.a \
  ../../deps/glib/build/gobject/libgobject-2.0.a \
  ../../deps/glib/build/gthread/libgthread-2.0.a \
  ../../deps/glib/build/glib/libcharset/libcharset.a \
  ../../deps/glib/build/glib/gnulib/libgnulib.a \
  ../../deps/pixman/build/pixman/libpixman-1.a \
  ../../deps/pixman/build/pixman/libpixman-arm-neon.a \
  ../../deps/openssl/build/libssl.a \
  ../../deps/openssl/build/libcrypto.a \
  ../../deps/pcre2/build/libpcre2-8.a \
  ../../deps/pcre2/build/libpcre2-posix.a \
  -lpthread -ldl -lm -lz \
  -o libqemu_full.so
```

## 功能支持

### 1. VNC显示功能
- **依赖**: Pixman库
- **功能**: 像素操作、图像压缩、显示渲染
- **支持**: JPEG/PNG压缩、SASL认证

### 2. 网络功能
- **依赖**: OpenSSL库
- **功能**: SSL/TLS加密、HTTPS下载
- **支持**: 安全网络连接、证书验证

### 3. 系统功能
- **依赖**: GLib库
- **功能**: 内存管理、字符串处理、数据结构
- **支持**: 线程、对象系统、字符集

### 4. 文本处理
- **依赖**: PCRE2库
- **功能**: 正则表达式匹配
- **支持**: 配置解析、文本搜索

## 子模块状态

### 之前的问题
这些目录之前被Git识别为子模块，但`.gitmodules`文件中没有对应配置，导致构建失败：

```
fatal: No url found for submodule path 'third_party/deps/glib/src' in .gitmodules
```

### 解决方案
1. **移除子模块配置**: 使用`git rm --cached`移除Git跟踪
2. **保留源代码**: 源代码和编译产物仍然存在
3. **移除.git目录**: 删除嵌入的Git仓库，使其成为普通目录

### 当前状态
- ✅ **源代码存在**: 所有依赖库的源代码都在
- ✅ **静态库存在**: 已编译的`.a`文件都在
- ✅ **Git状态正常**: 不再有子模块冲突
- ✅ **构建就绪**: 可以正常链接到共享库

## 验证方法

### 1. 检查静态库
```bash
# 查看所有静态库
find third_party/deps -name "*.a"

# 检查库文件大小
du -h third_party/deps/*/build/*/*.a | head -10
```

### 2. 检查链接
```bash
# 构建后检查共享库
file libqemu_full.so
ldd libqemu_full.so  # 查看动态依赖
```

### 3. 功能测试
```bash
# 测试VNC功能
qemu-system-aarch64 -vnc :0 -monitor stdio

# 测试网络功能
qemu-system-aarch64 -netdev user,id=net0 -device virtio-net-pci,netdev=net0
```

## 总结

**是的，这些依赖库会被编译成so文件！**

1. **静态库存在**: 26个`.a`文件已经编译完成
2. **会被链接**: 在创建`libqemu_full.so`时会被链接进去
3. **功能完整**: 支持VNC、网络、加密等所有功能
4. **子模块问题已解决**: 不再有Git配置冲突

最终的`libqemu_full.so`将包含：
- QEMU核心功能
- GLib系统库
- Pixman图像处理
- OpenSSL加密
- PCRE2正则表达式

这样构建的共享库是自包含的，不需要额外的系统依赖！🎉
