# QEMU-HMOS — Progress & Next Goals

Updated: 2025-09-05

## What We Did

- VM lifecycle UX
  - Added persistent VM store via Preferences (`VmStore.ets`): load on startup, save after create/start/stop.
  - “Create → Start (Install)” flow: creating a VM now immediately launches QEMU in VNC install mode.
  - ISO auto-copy: when an ISO path is provided, copy it into app sandbox `files/isos/` and use that path.

- VNC install experience
  - Integrated noVNC viewer page (`VNCViewer.ets`).
    - Loads `rawfile/novnc/novnc.min.js` if present, else falls back to dynamic import of `novnc.esm.js`.
    - QEMU is started with `-display vnc=:1,websocket=on` so the WebView can connect to `ws://127.0.0.1:5901`.
  - Added `rawfile/novnc/README.txt` and placed a built ESM bundle `novnc.esm.js`.
  - Ignored local third-party build folders: `third_party/novnc/`, `third_party/novnc_bundle/`.

- Firmware handling
  - `FirmwareManager.ets`: if files-side UEFI is missing, copy from rawfile to `files/`.
  - API signature uses `UIAbilityContext` explicitly; no `any` casts.

- ArkTS strictness fixes
  - Removed `any/unknown` and in-place `ts-ignore` usages in `Index.ets`.
  - Replaced inline object-literal-as-type with explicit interfaces/classes.
  - Ensured `build()` has a single root container (Stack → Tabs; overlays live inside Stack).

- Native (N-API) stability
  - Introduced `napi_compat.h`: on device include official `<napi/native_api.h>`; on host tests fallback to `napi_simple.h`.
  - `napi_init.cpp` now uses:
    - Proper `napi_property_descriptor` (OHOS) with full-field initialization and `napi_default` attributes.
    - Proper `napi_module` registration on device; returns `napi_value` from Init.
  - Disabled the fake N-API stub by default (to avoid SIGBUS on device):
    - CMake option `USE_FAKE_NAPI` controls including `napi_impl.cpp`; default OFF.
  - Fixed `RdpClient` constructor to match header (no dangling members).

- CMake/toolchain fixes
  - Default `OHOS_NDK_HOME` to `/Users/caidingding233/Library/OpenHarmony/Sdk/18/native` (overridable via env var, with DevEco fallbacks).
  - Always use NDK clang/clang++; removed `-nostdinc/-nostdlib++/-std=c++98` that broke libc++.
  - Warnings about missing QEMU static libs are allowed (we dlopen `libqemu_full.so` at runtime).

- Git hygiene
  - Ignored heavy third-party folders and local prebuilts: `third_party/novnc/`, `third_party/novnc_bundle/`, `so_libs/`.
  - Pushed feature branch `feat/novnc-install-flow` (no giant binaries) for PR. Main has `.gitignore` patch.

## Build & Run

- Prereqs
  - DevEco Studio 5+, OpenHarmony SDK 18; NDK at `/Users/caidingding233/Library/OpenHarmony/Sdk/18/native`.
  - Place noVNC bundle:
    - Prefer `entry/src/main/resources/rawfile/novnc/novnc.min.js` (official/prebuilt UMD), or
    - Use provided `novnc.esm.js` which the app dynamically imports.

- Commands
  - Clean: `hvigor clean`
  - Native only: `hvigor :entry:default@BuildNativeWithNinja`
  - Full build (debug): `hvigor assembleDebug`
  - Install: `hdc install -r ./entry/build/outputs/hap/*.hap`
  - Logs: `hdc shell hilog -x | grep QEMU_TEST`

- Runtime
  - Create VM → immediately launches in VNC install mode.
  - Ensure UEFI firmware exists under `files/` (auto-copied from rawfile on first run).
  - ISO path (if chosen) is auto-copied into `files/isos/` before launch.

## Next Goals

- Stability & UX
  - Add VM status/logs panel (wire up `getVmStatus`/`getVmLogs`) to diagnose install/runtime issues.
  - Improve VNC viewer UX (fit/canvas scaling, reconnect, error banners).

- RDP real backend
  - Integrate FreeRDP on device (guarded by feature flag), return real frames and input handling.
  - Keep current stub as fallback when FreeRDP is not bundled.

- Prebuilt binaries delivery
  - Don’t commit heavy prebuilts; publish `libqemu_full.so` to GitHub Releases (or internal storage) and add a `scripts/fetch_prebuilts.sh` to download + SHA256 verify into `entry/src/main/cpp/libs/arm64-v8a/`.
  - Add `docs/PrebuiltLibs.md` with version/URL/SHA and placement.

- CI & lint
  - Add a simple CI job to build ArkTS + native, and run ArkTS strict rules.
  - Keep `USE_FAKE_NAPI=OFF` for device builds to avoid ABI issues.

## Known Notes

- SIGBUS root cause was ABI mismatch when registering a custom N-API struct on device (fixed by using official OHOS N-API headers and registration).
- Large files (HAP-prebuilts, `.so`, firmware) should not be pushed to Git; prefer Releases or object storage.

