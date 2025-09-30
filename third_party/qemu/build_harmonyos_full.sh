#!/bin/bash
set -e

# 切换到脚本所在目录，保证相对路径正确
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"

echo "=== QEMU 鸿蒙完整功能编译脚本（上游源码） ==="
echo "目标：编译 aarch64-softmmu，开启 VNC/TCG/slirp 等核心能力"

CROSS_TRIPLE="${OHOS_CROSS_TRIPLE:-aarch64-unknown-linux-ohos}"

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
export PKG_CONFIG="$(basename "${PKG_CONFIG_SCRIPT}")"

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
  --cross-prefix=${CROSS_TRIPLE}- \
  --cc="$CC" \
  --host-cc="$HOST_CC" \
  --extra-cflags="-target ${CROSS_TRIPLE} --sysroot=${SYSROOT}" \
  --extra-ldflags="-target ${CROSS_TRIPLE} --sysroot=${SYSROOT}" \
  --enable-slirp \
  --enable-vnc \
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
