#!/bin/bash
set -e

# 切换到脚本所在目录，保证相对路径正确
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"

echo "=== QEMU 鸿蒙完整功能编译脚本（上游源码） ==="
echo "目标：编译 aarch64-softmmu，开启 VNC/TCG/slirp 等核心能力"

export OHOS_NDK_HOME="/Users/caidingding233/Library/OpenHarmony/Sdk/18/native"
export SYSROOT="${OHOS_NDK_HOME}/sysroot"
export CC="${OHOS_NDK_HOME}/llvm/bin/aarch64-unknown-linux-ohos-clang"
export CXX="${OHOS_NDK_HOME}/llvm/bin/aarch64-unknown-linux-ohos-clang++"
export AR="${OHOS_NDK_HOME}/llvm/bin/llvm-ar"
export STRIP="${OHOS_NDK_HOME}/llvm/bin/llvm-strip"
export RANLIB="${OHOS_NDK_HOME}/llvm/bin/llvm-ranlib"
export LD="${OHOS_NDK_HOME}/llvm/bin/ld.lld"
HOST_CC="/usr/bin/cc"

# pkg-config for cross
# Prefer aarch64-unknown-linux-ohos-pkg-config if available; else provide wrapper under deps/bin
WRAP_PKGCFG_DIR="${SCRIPT_DIR}/../deps/bin"
mkdir -p "$WRAP_PKGCFG_DIR"
cat >"$WRAP_PKGCFG_DIR/aarch64-unknown-linux-ohos-pkg-config" <<'EOF'
#!/bin/sh
export PKG_CONFIG_SYSROOT_DIR="${SYSROOT}"
export PKG_CONFIG_LIBDIR="${SYSROOT}/usr/lib/pkgconfig"
if [ "$#" -eq 0 ]; then
  exec pkg-config --version
else
  exec pkg-config "$@"
fi
EOF
chmod +x "$WRAP_PKGCFG_DIR/aarch64-unknown-linux-ohos-pkg-config"
export PATH="$WRAP_PKGCFG_DIR:$PATH"
export PKG_CONFIG="aarch64-unknown-linux-ohos-pkg-config"

# Provide nm wrapper expected by QEMU's cross-prefix
cat >"$WRAP_PKGCFG_DIR/aarch64-unknown-linux-ohos-nm" <<'EOF'
#!/bin/sh
exec /Users/caidingding233/Library/OpenHarmony/Sdk/18/native/llvm/bin/llvm-nm "$@"
EOF
chmod +x "$WRAP_PKGCFG_DIR/aarch64-unknown-linux-ohos-nm"
export PKG_CONFIG_LIBDIR="${SYSROOT}/usr/lib/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="${SYSROOT}"

echo "Using CC=${CC}"
echo "Using HOST_CC=${HOST_CC}"
echo "Using PKG_CONFIG=${PKG_CONFIG:-pkg-config}"

# 可选依赖预检查（关闭严格失败，交由 Meson 报错更精确）
${PKG_CONFIG:-pkg-config} --exists glib-2.0 || echo "WARN: glib-2.0 not found via pkg-config"
${PKG_CONFIG:-pkg-config} --exists pixman-1 || echo "WARN: pixman-1 not found via pkg-config"

BUILD_DIR="build_harmonyos_full"
rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "=== 配置 QEMU ./configure ==="
AR="$AR" STRIP="$STRIP" CXX="$CXX" \
HOST_CC="$HOST_CC" \
AR="$AR" STRIP="$STRIP" RANLIB="$RANLIB" CXX="$CXX" \
../configure \
  --target-list=aarch64-softmmu \
  --cross-prefix=aarch64-unknown-linux-ohos- \
  --cc="$CC" \
  --host-cc="$HOST_CC" \
  --extra-cflags="-target aarch64-unknown-linux-ohos --sysroot=${SYSROOT}" \
  --extra-ldflags="-target aarch64-unknown-linux-ohos --sysroot=${SYSROOT}" \
  -Db_staticpic=true -Db_pie=false -Ddefault_library=static \
  -Dtools=disabled \
  --enable-tcg \
  --enable-fdt=internal \
  --disable-kvm --disable-xen \
  --disable-werror \
  -Dvhost_user=disabled -Dvhost_user_blk_server=disabled -Dlibvduse=disabled -Dvduse_blk_export=disabled -Dvhost_net=disabled -Dvhost_kernel=disabled \
  -Dkeyring=disabled -Dguest_agent=disabled

echo "=== 开始编译 QEMU (make) ==="
make -j$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

echo "=== 构建完成，产出归档供链接 ==="
