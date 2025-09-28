# Repository Guidelines

## Project Structure & Module Organization
- ArkTS UI lives in `entry/src/main/ets/`; keep view logic under `pages/` and state in `viewmodel/`.
- Native bridge, QEMU launcher, and download helpers reside in `entry/src/main/cpp/`; headers and sources follow snake_case.
- Vendored QEMU sources build under `third_party/qemu/`; avoid editing unless syncing mirrors.
- App resources, including firmware assets like `QEMU_EFI.fd`, belong in `entry/src/main/resources/`.
- Developer scripts stay in `tools/`; CI or local helpers should land here with usage notes.
- Place build notes, architecture docs, and upgrade guides under `docs/` for quick discoverability.

## Build, Test, and Development Commands
- `hvigor assembleDebug`: build the full app (ArkTS + native) in debug mode from the repo root.
- `hvigor clean`: remove previous build outputs before a fresh build.
- `hvigor :entry:default@BuildNativeWithNinja`: rebuild only the native layer for tight iteration.
- Deploy with `hdc install -r ./entry/build/outputs/hap/*.hap` and inspect logs via `hdc shell hilog -x | grep QEMU_TEST`.

## Coding Style & Naming Conventions
- C++ uses LLVM style (`.clang-format`): 4-space indent, 120-column max, sorted `#include` blocks, short functions acceptable.
- Apply `.clang-tidy` suggestions; resolve unused parameter warnings and modernization hints before review.
- ArkTS components use PascalCase filenames (`Index.ets`), camelCase props/methods, and localized strings via resources.

## Testing Guidelines
- UI smoke tests live in `entry/src/ohosTest/`; run through DevEco Studio’s test runner for device validation.
- Exercise native NAPI flows from `Index.ets`; confirm JIT/KVM probing and VM lifecycle in hilog output.
- Prefer deterministic cases; capture logs or screenshots when diagnosing regressions.

## Commit & Pull Request Guidelines
- Follow Conventional Commits (`feat:`, `fix:`, `chore:`, etc.) with summaries under 72 characters.
- PR descriptions must cover purpose, key changes, affected modules, and attach test evidence (logs, GIFs) when relevant.
- Link related issues using `Closes #123` and keep scope narrowly focused for reviewability.

## Security & Configuration Tips
- Never commit secrets or signing certificates; keep local dev keys referenced in `build-profile.json5` only.
- Document the placement of large binaries (e.g., `libqemu_*.so`) and rely on `.gitignore` to block accidental commits.
- Ensure runtime gracefully falls back to TCG when JIT/KVM is unavailable; surface clear diagnostics in hilog.
