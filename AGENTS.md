# Repository Guidelines

## Project Structure & Module Organization
- `entry/src/main/ets/`: ArkTS UI, view models, diagnostics utilities.
- `entry/src/main/cpp/`: Native bridge (NAPI), QEMU orchestration, download helpers.
- `third_party/qemu/`: Vendored QEMU sources, scripts like `build_harmonyos_full.sh`.
- `third_party/deps/`: Cross-built libraries (PCRE2, GLib, Pixman) managed via `tools/build_ohos_deps.sh`.
- `entry/src/main/resources/`: App assets and firmware payloads (e.g., `QEMU_EFI.fd`).
- `tools/`: Developer helpers including log collectors and build automation.

## Build, Test, and Development Commands
- `hvigor assembleDebug`: Build the ArkTS app in debug mode from repo root.
- `hvigor clean`: Clear ArkTS build outputs when switching branches.
- `hvigor :entry:default@BuildNativeWithNinja`: Rebuild only the native bridge.
- `third_party/qemu/build_harmonyos_full.sh`: Cross-compiles QEMU using the OpenHarmony NDK; call after `tools/build_ohos_deps.sh`.
- `tools/build_ohos_deps.sh`: Prepares musl-friendly GLib/Pixman/PCRE2 artifacts for CI and local builds.
- `hdc install -r entry/build/outputs/hap/*.hap`: Deploy the packaged app to a device or emulator.

## Coding Style & Naming Conventions
- C++: Follow LLVM style (`.clang-format`), 4-space indent, sorted includes, prefer `auto` per `.clang-tidy`.
- ArkTS: Components in PascalCase, methods/props camelCase; place pages under `pages/`, models under `viewmodel/`.
- Filenames: C++ `snake_case.cpp/h`, ArkTS `PascalCase.ets`; keep comments concise and purposeful.

## Testing Guidelines
- UI smoke tests live in `entry/src/ohosTest/`; run via DevEco Studio test runner.
- Native smoke validation: trigger NAPI entrypoints from `Index.ets`, then inspect `hdc shell hilog -x | grep QEMU_TEST` for VM lifecycle logs.
- Prioritize deterministic, single-purpose cases; attach relevant logs or captures when proposing fixes.

## Commit & Pull Request Guidelines
- Use Conventional commits (`feat:`, `fix:`, `docs:`) with <72 char subject lines.
- PRs must outline purpose, key changes, affected modules, and test evidence (logs, GIFs, or timestamps).
- Link issues via `Closes #123` and keep changes focused for quick review.

## Security & Configuration Tips
- Never commit certificates, keys, or large binaries; instead document placement (e.g., `libqemu_*.so` in `entry/src/main/cpp/libs/`).
- Ensure `build-profile.json5` points to developer-local signing material.
- QEMU auto-detects JIT/KVM; implementations must gracefully fall back to TCG when unavailable.
