#!/bin/bash
#
# Build libintl for HarmonyOS (OpenHarmony)
#
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
INSTALL_PREFIX="${1:-${SCRIPT_DIR}/../install-ohos}"

# Find NDK
if [[ -z "${OHOS_NDK_HOME}" ]]; then
    for candidate in \
        "/mnt/e/HMOS_SDK/linux/native" \
        "${HOME}/Library/OpenHarmony/Sdk/18/native" \
        "${SCRIPT_DIR}/../../../ohos-sdk/linux/native"; do
        if [[ -d "${candidate}" ]]; then
            OHOS_NDK_HOME="${candidate}"
            break
        fi
    done
fi

if [[ -z "${OHOS_NDK_HOME}" || ! -d "${OHOS_NDK_HOME}" ]]; then
    echo "Error: OHOS_NDK_HOME not found"
    exit 1
fi

LLVM_BIN="${OHOS_NDK_HOME}/llvm/bin"
SYSROOT="${OHOS_NDK_HOME}/sysroot"
CROSS_TRIPLE="aarch64-unknown-linux-ohos"

CC="${LLVM_BIN}/${CROSS_TRIPLE}-clang"
AR="${LLVM_BIN}/llvm-ar"
RANLIB="${LLVM_BIN}/llvm-ranlib"

echo "=== Building libintl for HarmonyOS ==="
echo "NDK: ${OHOS_NDK_HOME}"
echo "Install: ${INSTALL_PREFIX}"

mkdir -p "${INSTALL_PREFIX}/lib"
mkdir -p "${INSTALL_PREFIX}/include"

cd "${SCRIPT_DIR}"

# Compile
echo "Compiling intl.c..."
${CC} -c intl.c -o intl.o \
    --sysroot="${SYSROOT}" \
    -fPIC \
    -O2 \
    -Wall \
    -I"${INSTALL_PREFIX}/include"

# Create static library
echo "Creating libintl.a..."
${AR} rcs "${INSTALL_PREFIX}/lib/libintl.a" intl.o
${RANLIB} "${INSTALL_PREFIX}/lib/libintl.a"

# Create shared library
echo "Creating libintl.so..."
${CC} -shared -o "${INSTALL_PREFIX}/lib/libintl.so" intl.o \
    --sysroot="${SYSROOT}" \
    -fPIC

# Install header
echo "Installing header..."
cp libintl.h "${INSTALL_PREFIX}/include/"

# Create pkg-config file
echo "Creating intl.pc..."
cat > "${INSTALL_PREFIX}/lib/pkgconfig/intl.pc" << EOF
prefix=${INSTALL_PREFIX}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: intl
Description: GNU gettext internationalization library (HarmonyOS implementation)
Version: 1.0.0
Libs: -L\${libdir} -lintl
Cflags: -I\${includedir}
EOF

# Cleanup
rm -f intl.o

echo ""
echo "=== libintl build complete ==="
ls -la "${INSTALL_PREFIX}/lib/libintl."*
echo ""

