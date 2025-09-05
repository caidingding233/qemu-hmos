# Prebuilt QEMU Core Library

This app’s N-API module (`libqemu_hmos.so`) dynamically loads a separate QEMU core library at runtime and calls its `qemu_main`:

- Core library: `libqemu_full.so`
- Load mechanism: `dlopen("libqemu_full.so", RTLD_NOW)` + `dlsym("qemu_main")`

## Placement

Place the prebuilt `libqemu_full.so` for `arm64-v8a` here so it is packed into the HAP:

- `entry/src/main/cpp/libs/arm64-v8a/libqemu_full.so`

The build system will package it under the app’s `lib/arm64` directory and it will be discoverable by name at runtime.

## Verify at Runtime

- On start VM, the app will log whether the core library is loaded:
  - Success: `[QEMU] Core library loaded, entering qemu_main...`
  - Failure: `[QEMU] dlopen libqemu_full.so failed: <reason>`
  - Fallback: `[QEMU] Core library missing, running stub loop`

Use: `hdc shell hilog -x | grep QEMU` to check logs.

## Notes

- Keep large prebuilts out of Git; distribute via Releases or internal storage.
- Record the SHA256 and version of the core library alongside download instructions.
