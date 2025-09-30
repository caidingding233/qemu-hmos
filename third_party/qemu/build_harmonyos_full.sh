#!/bin/bash
set -e

# 切换到脚本所在目录，保证相对路径正确
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"

echo "=== QEMU 鸿蒙完整功能编译脚本（上游源码） ==="
echo "目标：编译 aarch64-softmmu，开启 VNC/TCG/SLIRP 等核心能力；禁用在 OHOS 上不适用或引入 glibc 依赖的特性"

# 强制使用 OHOS 三元组，避免环境变量污染
CROSS_TRIPLE="aarch64-unknown-linux-ohos"

if [ -z "${OHOS_NDK_HOME:-}" ]; then
  for candidate in \
    "${SCRIPT_DIR}/../../ohos-sdk/linux/native" \
    "${HOME}/Library/OpenHarmony/Sdk/18/native" \
    "${HOME}/OpenHarmony/Sdk/18/native" \
    "${HOME}/openharmony/sdk/18/native"; do
    if [ -d "${candidate}" ]; then
      OHOS_NDK_HOME="${candidate}"
      break
    fi
  done
fi

if [ -z "${OHOS_NDK_HOME:-}" ]; then
  echo "error: set OHOS_NDK_HOME to your OpenHarmony NDK (native) directory" >&2
  exit 1
fi

export OHOS_NDK_HOME
SYSROOT="${OHOS_SYSROOT:-${OHOS_NDK_HOME}/sysroot}"
if [ ! -d "${SYSROOT}" ]; then
  echo "error: sysroot not found at ${SYSROOT}" >&2
  exit 1
fi
export SYSROOT

LLVM_BIN="${OHOS_NDK_HOME}/llvm/bin"
export CC="${OHOS_CC:-${LLVM_BIN}/${CROSS_TRIPLE}-clang}"
export CXX="${OHOS_CXX:-${LLVM_BIN}/${CROSS_TRIPLE}-clang++}"
export AR="${OHOS_AR:-${LLVM_BIN}/llvm-ar}"
export STRIP="${OHOS_STRIP:-${LLVM_BIN}/llvm-strip}"
export RANLIB="${OHOS_RANLIB:-${LLVM_BIN}/llvm-ranlib}"
export LD="${OHOS_LD:-${LLVM_BIN}/ld.lld}"
HOST_CC="${HOST_CC:-/usr/bin/cc}"

for tool in "${CC}" "${CXX}" "${AR}" "${RANLIB}" "${STRIP}" "${LD}"; do
  if [ ! -x "${tool}" ]; then
    echo "error: required tool not executable: ${tool}" >&2
    exit 1
  fi
done

# pkg-config for cross
# Prefer aarch64-unknown-linux-ohos-pkg-config if available; else provide wrapper under deps/bin
DEPS_PREFIX="${OHOS_DEPS_PREFIX:-${SCRIPT_DIR}/../deps/install-ohos}"
DEPS_PKGCONFIG="${DEPS_PREFIX}/lib/pkgconfig"
WRAP_PKGCFG_DIR="${SCRIPT_DIR}/../deps/bin"
mkdir -p "$WRAP_PKGCFG_DIR"
PKG_CONFIG_SCRIPT="$WRAP_PKGCFG_DIR/${CROSS_TRIPLE}-pkg-config"
cat >"${PKG_CONFIG_SCRIPT}" <<EOF
#!/bin/sh
EXTRA_PKGCFG="${DEPS_PKGCONFIG}"
SYSROOT_LIBDIR="${SYSROOT}/usr/lib/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="${SYSROOT}"
# 强制禁用系统搜索路径，避免回退到宿主 .pc
export PKG_CONFIG_PATH=""
if [ -d "\$EXTRA_PKGCFG" ]; then
  export PKG_CONFIG_LIBDIR="\$EXTRA_PKGCFG:\${SYSROOT_LIBDIR}"
else
  export PKG_CONFIG_LIBDIR="\${SYSROOT_LIBDIR}"
fi
if [ "\$#" -eq 0 ]; then
  exec pkg-config --version
else
  exec pkg-config "\$@"
fi
EOF
chmod +x "${PKG_CONFIG_SCRIPT}"
export PATH="$WRAP_PKGCFG_DIR:$PATH"
# 使用绝对路径，确保 configure/meson 不会意外调用宿主 pkg-config
export PKG_CONFIG="${PKG_CONFIG_SCRIPT}"

# Provide nm wrapper expected by QEMU's cross-prefix
NM_WRAPPER="$WRAP_PKGCFG_DIR/${CROSS_TRIPLE}-nm"
cat >"${NM_WRAPPER}" <<EOF
#!/bin/sh
exec "${LLVM_BIN}/llvm-nm" "\$@"
EOF
chmod +x "${NM_WRAPPER}"
if [ -d "${DEPS_PKGCONFIG}" ]; then
  export PKG_CONFIG_LIBDIR="${DEPS_PKGCONFIG}:${SYSROOT}/usr/lib/pkgconfig"
else
  export PKG_CONFIG_LIBDIR="${SYSROOT}/usr/lib/pkgconfig"
fi
export PKG_CONFIG_SYSROOT_DIR="${SYSROOT}"
# 禁止 pkg-config 扫描系统默认路径，防止 /usr/include 混入
export PKG_CONFIG_SYSTEM_INCLUDE_PATH=""
export PKG_CONFIG_SYSTEM_LIBRARY_PATH=""

# 清理可能注入宿主头/库的环境变量
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH LIBRARY_PATH SDKROOT
# 清空通用编译标志，避免遗留 --target=aarch64-linux-gnu 或 -I/usr/include 等
export CFLAGS=""
export CXXFLAGS=""
export LDFLAGS=""
export CPPFLAGS=""

echo "Using CC=${CC}"
echo "Using HOST_CC=${HOST_CC}"
echo "Using PKG_CONFIG=${PKG_CONFIG:-pkg-config}"

# 依赖前置校验：必须命中我们交叉构建的 .pc 文件，避免回退宿主
if ! "$PKG_CONFIG" --exists glib-2.0; then
  echo "error: missing glib-2.0.pc under ${DEPS_PKGCONFIG}; run tools/build_ohos_deps.sh" >&2
  exit 1
fi
if ! "$PKG_CONFIG" --exists pixman-1; then
  echo "error: missing pixman-1.pc under ${DEPS_PKGCONFIG}; run tools/build_ohos_deps.sh" >&2
  exit 1
fi
echo "glib-2.0 cflags: $($PKG_CONFIG --cflags glib-2.0)"
echo "pixman-1 cflags: $($PKG_CONFIG --cflags pixman-1)"

BUILD_DIR="build_harmonyos_full"
rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "=== 配置 QEMU ./configure ==="

#
# 功能裁剪说明（面向 OHOS 设备）：
#
# 已启用（需要）：
#   - VNC: 远程显示（基础，不启用 PNG/JPEG/TLS 扩展，减少依赖）
#   - SLIRP: 用户态网络（来宾网络上网能力）
#   - TCG: 纯软件翻译（无 KVM/Xen）
#   - FDT(internal): 使用内置 dtc，避免外部依赖
#
# 已禁用（不需要 / OHOS 不支持 / 依赖繁重）：
#   - KVM/Xen/Virt accel/vhost: 设备上无对应内核/权限
#   - 本地 GUI: SDL/GTK/VTE/curses/SPICE/brlapi/usbredir
#   - 安全/压缩扩展: gnutls/nettle/gcrypt/ssl/curl/ssh/lzo/snappy/bzip2/zstd/lzfse
#   - 其他：keyring、guest-agent（需要时可单独交叉构建）、tools（qemu-img 等，默认关闭）
#

AR="$AR" STRIP="$STRIP" CXX="$CXX" \
HOST_CC="$HOST_CC" \
AR="$AR" STRIP="$STRIP" RANLIB="$RANLIB" CXX="$CXX" \
MESON_BIN=$(command -v meson || true)
../configure \
  --target-list=aarch64-softmmu \
  --cross-prefix=${CROSS_TRIPLE}- \
  --cc="$CC" \
  --host-cc="$HOST_CC" \
  --cross-cc-cflags-aarch64="-target ${CROSS_TRIPLE} --sysroot=${SYSROOT}" \
  --extra-cflags="-target ${CROSS_TRIPLE} --sysroot=${SYSROOT}" \
  --extra-ldflags="-target ${CROSS_TRIPLE} --sysroot=${SYSROOT}" \
  ${MESON_BIN:+--meson="$MESON_BIN"} \
  --pkg-config="$PKG_CONFIG" \
  --enable-slirp \
  --enable-vnc \
  --enable-tcg \
  --enable-fdt=internal \
  \
  --disable-kvm \
  --disable-xen \
  --disable-werror \
  --disable-gio \
  \
  --disable-sdl \
  --disable-gtk \
  --disable-vte \
  --disable-curses \
  --disable-spice \
  --disable-brlapi \
  --disable-usb-redir \
  \
  --disable-gnutls \
  --disable-nettle \
  --disable-gcrypt \
  --disable-libssh \
  --disable-curl \
  --disable-lzo \
  --disable-snappy \
  --disable-bzip2 \
  --disable-lzfse \
  --disable-zstd \
  \
  -Db_staticpic=true \
  -Db_pie=false \
  -Ddefault_library=static \
  -Dtools=disabled \
  -Dvhost_user=disabled \
  -Dvhost_user_blk_server=disabled \
  -Dlibvduse=disabled \
  -Dvduse_blk_export=disabled \
  -Dvhost_net=disabled \
  -Dvhost_kernel=disabled \
  -Dkeyring=disabled \
  -Dguest_agent=disabled

echo "=== 开始编译 QEMU (make) ==="
make -j$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

echo "=== 构建完成，产出归档供链接 ==="
