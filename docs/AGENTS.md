# Repository Guidelines

## Project Structure & Module Organization
- `entry/src/main/ets/`: ArkTS UI (VM, Apps, diagnostics).
- `entry/src/main/cpp/`: Native bridge (NAPI), QEMU launcher, download utils.
- `third_party/qemu/`: Vendored QEMU sources/build artifacts (aarch64 target).
- `entry/src/main/resources/`: App resources; place firmware like `QEMU_EFI.fd`.
- `tools/`: Developer scripts (e.g., `hdc_collect_qemu.sh`).
- `docs/`: Build notes for QEMU/OHOS.

## Build, Test, and Development Commands
- Build app (debug): `hvigor assembleDebug` (from repo root).
- Clean: `hvigor clean`.
- Native only: `hvigor :entry:default@BuildNativeWithNinja`.
- Run on device: Use DevEco Studio Run, or `hdc install -r ./entry/build/outputs/hap/*.hap`.
- Verify logs: `hdc shell hilog -x | grep QEMU_TEST`.

## Coding Style & Naming Conventions
- C++: LLVM style via `.clang-format` (4‑space indent, 120 col limit). Keep headers local, `#include` ordering sorted, short functions acceptable.
- Lint: `.clang-tidy` enabled; fix warnings for unused params/vars, modernize‑use‑auto, readability checks.
- ArkTS: Use PascalCase for components, camelCase for props/methods; keep files under `pages/` and `viewmodel/`.
- Filenames: C++ `snake_case.cpp/h`, ArkTS `PascalCase.ets`.

## Testing Guidelines
- UI smoke tests live in `entry/src/ohosTest/`; run via DevEco’s test runner.
- Native smoke: exercise NAPI from `Index.ets`; confirm JIT/KVM flags and VM start/stop in hilog.
- Aim for small, deterministic cases; attach logs or screenshots in PRs.

## Commit & Pull Request Guidelines
- Commit messages: Conventional style — `feat: …`, `fix: …`, `docs: …`, `chore: …`. Keep < 72 chars summary, body optional.
- PRs must include: purpose, key changes, test evidence (logs/GIFs), affected modules/paths, and any migration notes.
- Link issues with `Closes #123`. Keep PRs focused and reviewable.

## Security & Configuration Tips
- Do not commit certificates or secrets. Paths in `build-profile.json5` should point to local dev keys.
- JIT/KVM are probed at runtime; code should gracefully degrade to TCG.
- Large binaries: prefer `.gitignore` + document placement (e.g., `libqemu_*.so` under `entry/src/main/cpp/libs/`).
