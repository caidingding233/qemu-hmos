# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

This is a QEMU virtualization app for HarmonyOS NEXT that runs Windows/Linux ARM64 virtual machines on HarmonyOS tablets and computers. The project embeds QEMU as a native library (.so) and provides a HarmonyOS app interface with RDP/VNC display capabilities.

## Build System & Development Commands

### Core Build Commands
- **Build app (debug)**: `hvigor assembleDebug` (from repo root)
- **Build app (release)**: `hvigor assembleRelease`
- **Clean build**: `hvigor clean`
- **Native library only**: `hvigor :entry:default@BuildNativeWithNinja`
- **Install on device**: `hdc install -r ./entry/build/outputs/hap/*.hap`

### Development & Testing
- **View logs**: `hdc shell hilog -x | grep QEMU_TEST`
- **Check VM status**: `hdc shell hilog -x | grep QEMU_CORE`
- **Debug VNC connectivity**: `./detailed_vnc_debug.sh`
- **Comprehensive diagnostics**: `./comprehensive_debug.sh`
- **Check QEMU status**: `./check_qemu_status.sh`

### QEMU-specific Build
The project requires a pre-built QEMU library (`libqemu_full.so`) to be placed in `entry/src/main/cpp/libs/arm64-v8a/`. QEMU should be configured with:
```bash
./configure --target-list=aarch64-softmmu \
            --enable-tcg --disable-debug-info \
            --disable-modules
make -j$(nproc)
```

## Architecture Overview

### High-Level Structure
- **Frontend**: ArkTS UI (HarmonyOS native UI framework)
- **Backend**: C++ NAPI bridge to embedded QEMU library
- **Virtualization**: QEMU aarch64-softmmu with TCG JIT (KVM fallback)
- **Display**: VNC for installation, RDP for daily use
- **Networking**: QEMU user-net with port forwarding (offline-capable)

### Key Components

#### ArkTS Frontend (`entry/src/main/ets/`)
- **`pages/`**: Main UI pages (Index, VMs, Apps, VNCViewer, RDPViewer)
- **`managers/`**: Business logic (VmStore for persistence, VNCNativeClient)
- **`components/`**: Reusable UI components (RDPDisplay)
- **`utils/`**: Utilities (FirmwareManager for EDK2 UEFI handling)
- **`workers/`**: Background threads (qemu_worker.ts)

#### Native Bridge (`entry/src/main/cpp/`)
- **`napi_init.cpp`**: Main NAPI module exposing QEMU functions to ArkTS
- **`qemu_wrapper.cpp`**: C++ wrapper around libqemu APIs
- **`rdp_client.cpp`**: RDP client implementation for guest display

#### QEMU Integration
- **`third_party/qemu/`**: Vendored QEMU source/build artifacts
- **Target**: aarch64-softmmu (ARM64 system emulation)
- **Acceleration**: Runtime detection of KVM → TCG JIT fallback
- **Firmware**: EDK2 UEFI (`QEMU_EFI.fd` in app resources)

### Data Flow
1. **VM Creation**: ArkTS UI → NAPI → VmStore persistence → QEMU config generation
2. **VM Execution**: NAPI spawns QEMU thread with generated command line
3. **Display**: VNC (setup) → RDP (daily use) via localhost port forwarding
4. **File Sharing**: RDP drive redirection maps app sandbox to guest Z: drive

## Configuration & Environment

### HarmonyOS Development
- **Required**: DevEco Studio 5+, HarmonyOS NEXT SDK (API 12+)
- **Signing**: Developer certificate + debug signature (enables JIT execution)
- **Device**: HarmonyOS NEXT tablet/computer with developer options enabled

### Build Dependencies (Native)
- **Host tools**: cmake, ninja, C/C++ toolchain
- **Cross-compilation**: Uses HarmonyOS NDK toolchain for aarch64-linux-ohos
- **Libraries**: QEMU static libs, libvncclient, FreeRDP dependencies

## Coding Standards

### C++ (from AGENTS.md)
- **Style**: LLVM format via `.clang-format` (4-space indent, 120 column limit)
- **Linting**: `.clang-tidy` enabled for modernization and readability
- **Naming**: `snake_case.cpp/.h` files
- **Headers**: Local includes, sorted ordering, short functions acceptable

### ArkTS
- **Components**: PascalCase for components, camelCase for props/methods
- **Files**: PascalCase.ets, organized under `pages/` and `viewmodel/`
- **Architecture**: Follows HarmonyOS UI framework patterns

## Testing & Verification

### UI Testing
- **Location**: `entry/src/ohosTest/` - run via DevEco test runner
- **Scope**: UI smoke tests for main app workflows

### Native Testing
- **NAPI validation**: Exercise from `Index.ets`, check JIT/KVM flags in hilog
- **VM lifecycle**: Test start/stop operations with status monitoring
- **Integration**: End-to-end tests in `test_e2e_qemu_integration.cpp`

## Security & Performance

### JIT & KVM Handling
- **Runtime probing**: Attempts `/dev/kvm` access, gracefully degrades to TCG
- **JIT enablement**: Requires developer signature, uses `prctl("jit", 1)`
- **Performance**: TCG JIT provides reasonable performance when KVM unavailable

### Resource Management
- **Memory**: Default 6GB RAM allocation per VM
- **Storage**: QCOW2 disk images with 64GB default size
- **Network**: Isolated user-net with selective port forwarding

## File Organization Specifics

### Critical Paths
- **Native libs**: `entry/src/main/cpp/libs/arm64-v8a/libqemu_full.so`
- **Firmware**: `entry/src/main/resources/rawfile/QEMU_EFI.fd`
- **VM configs**: Managed by VmStore in app data directory
- **Build output**: `entry/build/outputs/hap/`

### Git Management
- **Ignored**: Large binaries (QEMU .so files), build artifacts, certificates
- **Tracked**: Source code, configuration templates, documentation
- **Secrets**: Build profiles contain local dev certificate paths (not committed)

## Troubleshooting

### Common Issues
- **KVM unavailable**: Expected on most devices, auto-fallback to TCG
- **JIT disabled**: Check developer certificate and device developer options
- **RDP connection**: Verify VM has remote desktop enabled, check port 3390 forwarding
- **VNC during install**: Use VNC viewer initially, switch to RDP post-install

### Debug Commands
- **VM status**: Check logs with `hdc shell hilog -x | grep QEMU`
- **Native diagnostics**: Use provided shell scripts in project root
- **Build issues**: Verify OHOS_NDK_HOME and QEMU library placement

## Integration Points

### HarmonyOS APIs
- **File system**: App sandbox access for VM storage and ISO handling
- **Networking**: System network APIs for display connectivity
- **UI framework**: ArkTS components for native HarmonyOS experience
- **Media**: AVSession integration for media control passthrough (WIP)

### QEMU Integration
- **Command line**: Generated dynamically based on VM configuration
- **Display**: VNC server during installation, RDP for normal operation  
- **Storage**: QCOW2 images with configurable sizes and caching
- **Network**: User-net with hostfwd for service access (RDP, SSH, etc.)