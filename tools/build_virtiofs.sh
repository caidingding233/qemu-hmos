#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[virtiofs-build] $*"
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

log "=== VirtioFS build helper (HarmonyOS) ==="
log "说明：QEMU 上游已不再内置 virtiofsd，这里做两件事："
log "  1) 确保 QEMU 构建时启用 vhost-user（virtiofs / vhost-user-fs 依赖）"
log "  2) 提示你准备外部 virtiofsd / vhost-user-fs backend（本仓库不内置源码）"

export AETHER_ENABLE_VIRTIOFS=1

log ""
log "Step 1/2: build libqemu_full.so with vhost-user enabled"
bash "${REPO_ROOT}/tools/build_qemu_full_linux.sh"

log ""
log "Step 2/2: virtiofsd backend"
log "⚠️  当前仓库未包含 virtiofsd 源码/二进制。"
log "   你需要自行准备一个 vhost-user-fs backend（例如 Rust virtiofsd），并在运行时通过 socket 连接给 QEMU。"
log "   参考：third_party/qemu/docs/system/devices/virtio/vhost-user.rst"
