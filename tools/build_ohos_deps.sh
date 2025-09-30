#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[ohos-deps] %s\n' "$*"
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
DEPS_ROOT="${REPO_ROOT}/third_party/deps"
DEFAULT_PREFIX="${DEPS_ROOT}/install-ohos"
PREFIX="${OHOS_DEPS_PREFIX:-${DEFAULT_PREFIX}}"
BUILD_ROOT="${DEPS_ROOT}/.ohos-build"
TOOLCHAIN_DIR="${BUILD_ROOT}/toolchain"
CROSS_TRIPLE="${OHOS_CROSS_TRIPLE:-aarch64-unknown-linux-ohos}"

if [[ -n "${OHOS_NDK_HOME:-}" ]]; then
  NDK_ROOT="${OHOS_NDK_HOME}"
else
  for candidate in \
    "${REPO_ROOT}/ohos-sdk/linux/native" \
    "${HOME}/Library/OpenHarmony/Sdk/18/native" \
    "${HOME}/OpenHarmony/Sdk/18/native" \
    "${HOME}/openharmony/sdk/18/native"; do
    if [[ -d "${candidate}" ]]; then
      NDK_ROOT="${candidate}"
      break
    fi
  done
fi

if [[ -z "${NDK_ROOT:-}" ]]; then
  log "error: set OHOS_NDK_HOME to your OpenHarmony NDK (native) directory"
  exit 1
fi

SYSROOT="${OHOS_SYSROOT:-${NDK_ROOT}/sysroot}"
if [[ ! -d "${SYSROOT}" ]]; then
  log "error: sysroot not found at ${SYSROOT}"
  exit 1
fi

CLANG_BIN="${NDK_ROOT}/llvm/bin/${CROSS_TRIPLE}-clang"
CXX_BIN="${NDK_ROOT}/llvm/bin/${CROSS_TRIPLE}-clang++"
AR_BIN="${NDK_ROOT}/llvm/bin/llvm-ar"
RANLIB_BIN="${NDK_ROOT}/llvm/bin/llvm-ranlib"
NM_BIN="${NDK_ROOT}/llvm/bin/llvm-nm"
STRIP_BIN="${NDK_ROOT}/llvm/bin/llvm-strip"
LD_BIN="${NDK_ROOT}/llvm/bin/ld.lld"

for tool in "${CLANG_BIN}" "${CXX_BIN}" "${AR_BIN}" "${RANLIB_BIN}" "${NM_BIN}" "${STRIP_BIN}" "${LD_BIN}"; do
  if [[ ! -x "${tool}" ]]; then
    log "error: required tool not executable: ${tool}"
    exit 1
  fi
done

mkdir -p "${PREFIX}" "${BUILD_ROOT}" "${TOOLCHAIN_DIR}"
mkdir -p "${PREFIX}/lib/pkgconfig"

PKG_CONFIG_WRAPPER="${TOOLCHAIN_DIR}/${CROSS_TRIPLE}-pkg-config"
cat >"${PKG_CONFIG_WRAPPER}" <<EOF_SCRIPT
#!/bin/sh
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/pkgconfig:${SYSROOT}/usr/lib/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="${SYSROOT}"
exec pkg-config "\$@"
EOF_SCRIPT
chmod +x "${PKG_CONFIG_WRAPPER}"

MESON_CROSS_FILE="${TOOLCHAIN_DIR}/${CROSS_TRIPLE}.ini"
cat >"${MESON_CROSS_FILE}" <<EOF_SCRIPT
[binaries]
c = '${CLANG_BIN}'
cpp = '${CXX_BIN}'
ar = '${AR_BIN}'
strip = '${STRIP_BIN}'
pkg-config = '${PKG_CONFIG_WRAPPER}'
ld = '${LD_BIN}'
cmake = 'cmake'
python = 'python3'

[properties]
needs_exe_wrapper = true
sys_root = '${SYSROOT}'

[built-in options]
c_args = ['--target=${CROSS_TRIPLE}', '--sysroot=${SYSROOT}', '-fPIC']
cpp_args = ['--target=${CROSS_TRIPLE}', '--sysroot=${SYSROOT}', '-fPIC']
c_link_args = ['--target=${CROSS_TRIPLE}', '--sysroot=${SYSROOT}']
cpp_link_args = ['--target=${CROSS_TRIPLE}', '--sysroot=${SYSROOT}']

[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF_SCRIPT

CMAKE_TOOLCHAIN_FILE="${TOOLCHAIN_DIR}/${CROSS_TRIPLE}-toolchain.cmake"
cat >"${CMAKE_TOOLCHAIN_FILE}" <<EOF_SCRIPT
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_SYSROOT "${SYSROOT}")
set(CMAKE_C_COMPILER "${CLANG_BIN}")
set(CMAKE_C_COMPILER_TARGET "${CROSS_TRIPLE}")
set(CMAKE_AR "${AR_BIN}")
set(CMAKE_RANLIB "${RANLIB_BIN}")
set(CMAKE_NM "${NM_BIN}")
set(CMAKE_STRIP "${STRIP_BIN}")
set(CMAKE_C_FLAGS_INIT "--target=${CROSS_TRIPLE} --sysroot=${SYSROOT} -fPIC")
set(CMAKE_EXE_LINKER_FLAGS_INIT "--target=${CROSS_TRIPLE} --sysroot=${SYSROOT}")
set(CMAKE_FIND_ROOT_PATH "${PREFIX}" "${SYSROOT}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
EOF_SCRIPT

export PKG_CONFIG="${PKG_CONFIG_WRAPPER}"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/pkgconfig:${SYSROOT}/usr/lib/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="${SYSROOT}"

build_pcre2() {
  local src="${DEPS_ROOT}/pcre2/src"
  local build_dir="${DEPS_ROOT}/pcre2/build-ohos"
  log "configuring PCRE2"
  rm -rf "${build_dir}"
  cmake -S "${src}" -B "${build_dir}" \
    -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${CMAKE_TOOLCHAIN_FILE}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DBUILD_SHARED_LIBS=OFF \
    -DPCRE2_BUILD_PCRE2_16=OFF \
    -DPCRE2_BUILD_PCRE2_32=OFF \
    -DPCRE2_BUILD_TESTS=OFF \
    -DPCRE2_BUILD_PCRE2GREP=OFF \
    -DPCRE2_BUILD_PCRE2GREP_PCRE2_8=OFF \
    -DPCRE2_SUPPORT_JIT=OFF
  cmake --build "${build_dir}"
  cmake --install "${build_dir}"
}

build_glib() {
  local src="${DEPS_ROOT}/glib/src"
  local build_dir="${DEPS_ROOT}/glib/build-ohos"
  log "configuring GLib"
  # Ensure vendored Meson subprojects are present; when the GLib git submodule
  # is checked out with --depth=1, nested submodules such as gvdb may be left
  # uninitialised which forces Meson to attempt a network download (blocked by
  # --wrap-mode=nodownload). Initialise the required ones if they are missing.
  if git -C "${src}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    declare -a missing_subprojects=()
    for sp in gvdb libffi proxy-libintl; do
      if [[ ! -f "${src}/subprojects/${sp}/meson.build" ]]; then
        missing_subprojects+=("subprojects/${sp}")
      fi
    done
    if ((${#missing_subprojects[@]})); then
      log "initialising GLib nested subprojects: ${missing_subprojects[*]}"
      git -C "${src}" submodule update --init --recursive "${missing_subprojects[@]}"
    fi
  fi

  # Ensure test template files exist; GLib's meson.build references them unconditionally
  if [[ ! -f "${src}/tests/template.test.in" ]] || [[ ! -f "${src}/tests/template-tap.test.in" ]]; then
    log "GLib test templates missing; creating minimal stubs"
    mkdir -p "${src}/tests"
    [[ -f "${src}/tests/template.test.in" ]] || cat >"${src}/tests/template.test.in" <<'GLIB_TEST_STUB'
[Test]
Type=session
Exec=@test_exec@
Output=@test_output@
GLIB_TEST_STUB
    [[ -f "${src}/tests/template-tap.test.in" ]] || cat >"${src}/tests/template-tap.test.in" <<'GLIB_TEST_TAP_STUB'
[Test]
Type=session
Exec=@test_exec@
Output=TAP
GLIB_TEST_TAP_STUB
  fi
  # GitHub Actions sets CI=true; GLib expects a GitLab-specific wrapper in that case.
  # Provide a benign stub so Meson does not fail when it tries to locate the script.
  if [[ ! -x "${src}/.gitlab-ci/thorough-test-wrapper.sh" ]]; then
    log "Stub .gitlab-ci/thorough-test-wrapper.sh for CI builds"
    mkdir -p "${src}/.gitlab-ci"
    cat >"${src}/.gitlab-ci/thorough-test-wrapper.sh" <<'GLIB_CI_STUB'
#!/bin/sh
# Minimal wrapper for CI environments that expect GitLab's thorough-test wrapper.
exec "$@"
GLIB_CI_STUB
    chmod +x "${src}/.gitlab-ci/thorough-test-wrapper.sh"
  fi
  rm -rf "${build_dir}"
  meson setup "${build_dir}" "${src}" \
    --cross-file "${MESON_CROSS_FILE}" \
    --prefix "${PREFIX}" \
    --libdir lib \
    --buildtype release \
    --default-library static \
    --wrap-mode=nodownload \
    -Dtests=false \
    -Dinstalled_tests=false \
    -Dintrospection=disabled \
    -Dsysprof=disabled \
    -Ddocumentation=false \
    -Dman-pages=disabled \
    -Dselinux=disabled \
    -Dxattr=false \
    -Dlibmount=disabled \
    -Dlibelf=disabled \
    -Dnls=disabled \
    -Dglib_debug=disabled \
    -Dglib_assert=false \
    -Dglib_checks=false \
    -Doss_fuzz=disabled
  ninja -C "${build_dir}"
  ninja -C "${build_dir}" install
}

build_pixman() {
  local src="${DEPS_ROOT}/pixman/src"
  local build_dir="${DEPS_ROOT}/pixman/build-ohos"
  log "configuring pixman"
  rm -rf "${build_dir}"
  meson setup "${build_dir}" "${src}" \
    --cross-file "${MESON_CROSS_FILE}" \
    --prefix "${PREFIX}" \
    --libdir lib \
    --buildtype release \
    --default-library static \
    --wrap-mode=nodownload \
    -Dgtk=disabled \
    -Dlibpng=disabled \
    -Dtests=disabled \
    -Ddemos=disabled \
    -Dopenmp=disabled \
    -Dgnuplot=false \
    -Dtimers=false
  ninja -C "${build_dir}"
  ninja -C "${build_dir}" install
}

build_pcre2
build_glib
build_pixman

log "artifacts installed under ${PREFIX}"
